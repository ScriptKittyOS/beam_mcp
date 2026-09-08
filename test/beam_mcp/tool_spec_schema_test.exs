# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.ToolSpecSchemaTest do
  @moduledoc """
  The catalog carries each tool's schema; the server validates against what it is handed.

  Before this change the server held a compiled-in clause per tool name and consulted nothing
  else, so a catalog could advertise a schema the server would never enforce -- `tools/list`
  showed one contract and `tools/call` applied another.
  """
  use ExUnit.Case, async: true

  alias BeamMCP.Server

  @novel_schema %{
    "type" => "object",
    "properties" => %{
      "widget_id" => %{
        "type" => "string",
        "description" => "A widget the server has never heard of."
      }
    },
    "required" => ["widget_id"],
    "additionalProperties" => false
  }

  defmodule CatalogWithSchema do
    @behaviour BeamMCP.Catalog

    @impl true
    def capabilities, do: %{tools: all_tools(), resources: [], prompts: []}

    defp all_tools do
      [
        %BeamMCP.ToolSpec{
          name: :inspect_widget,
          command_class: :observe,
          mode: :read_only,
          description: "A tool whose schema exists only in the catalog.",
          input_schema: %{
            "type" => "object",
            "properties" => %{"widget_id" => %{"type" => "string"}},
            "required" => ["widget_id"],
            "additionalProperties" => false
          }
        }
      ]
    end
  end

  defp state(dispatch \\ fn _n, _a, _o -> {:ok, %{}} end) do
    Server.new(dispatch: dispatch, catalog: CatalogWithSchema)
  end

  defp call(state, args) do
    Server.handle_message(state, %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "tools/call",
      "params" => %{"name" => "inspect_widget", "arguments" => args}
    })
  end

  test "tools/list advertises the schema the catalog carries" do
    {_s, resp} =
      Server.handle_message(state(), %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"})

    [tool] = resp["result"]["tools"]
    assert tool["inputSchema"]["required"] == ["widget_id"]
    assert tool["inputSchema"]["properties"]["widget_id"]["type"] == "string"
  end

  test "a call missing a required property the catalog declared is refused" do
    {_s, resp} = call(state(), %{})

    assert resp["result"]["isError"],
           "the server accepted a call that violates the schema its own catalog advertises"

    # The error is a JSON object now, not a string: `=~` no longer applies to it.
    assert resp["result"]["structuredContent"]["error"]["reason"] =~ "widget_id"
  end

  test "a call carrying a property the catalog's schema forbids is refused" do
    {_s, resp} = call(state(), %{"widget_id" => "w-1", "not_declared" => true})

    assert resp["result"]["isError"],
           "additionalProperties: false was advertised and not enforced"
  end

  test "a valid call reaches dispatch with keys from the catalog's schema" do
    parent = self()

    dispatch = fn name, args, _o ->
      send(parent, {:dispatch, name, args})
      {:ok, %{}}
    end

    {_s, resp} = call(state(dispatch), %{"widget_id" => "w-1"})

    assert_receive {:dispatch, :inspect_widget, args}, 200
    assert args[:widget_id] == "w-1"
    refute resp["result"]["isError"]
  end

  test "the schema is data, so a spec the server has never seen still governs" do
    # Built here, not in any module the server compiled against.
    assert @novel_schema["required"] == ["widget_id"]
    assert Map.has_key?(@novel_schema["properties"], "widget_id")
  end
end
