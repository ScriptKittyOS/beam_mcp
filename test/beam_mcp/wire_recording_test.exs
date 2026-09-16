# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.WireRecordingTest do
  @moduledoc """
  The wire before and after the connectome surface: `test/fixtures/wire/pre-017.json` is what
  the five advertising methods answered, on the core and through the HTTP transport, for the
  fixture catalog on the tree before `BeamMCP.Connectome.Surface` existed. This file holds
  that the same catalog still answers exactly that, and that the catalog with the surface's
  entries added answers exactly that plus the entries -- nothing else on the wire moved, and
  `server/discover` is byte-identical: no capability was claimed for a graph.
  """
  use ExUnit.Case, async: true

  alias BeamMCP.Connectome.Surface
  alias BeamMCP.Fixture.Declared.Catalog, as: Fixture
  alias BeamMCP.Wire.Recorder

  @pre Path.expand("../fixtures/wire/pre-017.json", __DIR__)

  defmodule WithSurface do
    @behaviour BeamMCP.Catalog
    @impl true
    def capabilities do
      caps = Fixture.capabilities()

      %{
        caps
        | tools: caps.tools ++ [Surface.tool()],
          resources: caps.resources ++ Surface.resources()
      }
    end

    @impl true
    def read_resource(uri), do: Fixture.read_resource(uri)
    @impl true
    def get_prompt(name, args), do: Fixture.get_prompt(name, args)
  end

  test "the fixture catalog still answers the pre-slice recording, byte for byte" do
    assert Recorder.record(Fixture, server_name: "fixture") == Jason.decode!(File.read!(@pre))
  end

  test "with the surface's entries the wire is the recording plus exactly those entries" do
    pre = Jason.decode!(File.read!(@pre))
    post = Recorder.record(WithSurface, server_name: "fixture")

    assert post["server/discover"] == pre["server/discover"]
    assert post["prompts/list"] == pre["prompts/list"]
    assert post["resources/templates/list"] == pre["resources/templates/list"]

    for transport <- ["core", "http"] do
      tools_pre = get_in(pre, ["tools/list", transport, "result", "tools"])
      tools_post = get_in(post, ["tools/list", transport, "result", "tools"])
      assert tools_post -- tools_pre == [connectome_tool_definition()], transport
      assert tools_pre -- tools_post == [], transport

      res_pre = get_in(pre, ["resources/list", transport, "result", "resources"])
      res_post = get_in(post, ["resources/list", transport, "result", "resources"])

      assert Enum.map(res_post -- res_pre, & &1["uri"]) ==
               ~w(connectome://declared connectome://diff connectome://observed),
             transport

      assert res_pre -- res_post == [], transport
    end

    # Everything but the two lists' entries is identical: strip the entries and compare whole.
    strip = fn rec ->
      rec
      |> update_in(
        ["tools/list", "core", "result", "tools"],
        &Enum.reject(&1, fn t -> t["name"] == "connectome" end)
      )
      |> update_in(
        ["tools/list", "http", "result", "tools"],
        &Enum.reject(&1, fn t -> t["name"] == "connectome" end)
      )
      |> update_in(
        ["resources/list", "core", "result", "resources"],
        &Enum.reject(&1, fn r -> String.starts_with?(r["uri"], "connectome://") end)
      )
      |> update_in(
        ["resources/list", "http", "result", "resources"],
        &Enum.reject(&1, fn r -> String.starts_with?(r["uri"], "connectome://") end)
      )
    end

    assert strip.(post) == pre
  end

  defp connectome_tool_definition do
    tool = Surface.tool()

    %{
      "name" => "connectome",
      "description" => tool.description,
      "inputSchema" => tool.input_schema,
      "annotations" => %{
        "destructiveHint" => false,
        "idempotentHint" => true,
        "openWorldHint" => false,
        "readOnlyHint" => true
      }
    }
  end
end
