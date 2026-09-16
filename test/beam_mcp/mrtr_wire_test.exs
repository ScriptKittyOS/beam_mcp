# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.MrtrWireTest do
  @moduledoc """
  The behaviour behind the will-not-implement page's entry 12, on the wire: a request carrying
  `inputResponses` and `requestState` is served exactly as the bare request is, on the three
  methods the revision lets a server continue -- `tools/call`, `resources/read`, `prompts/get` --
  at both eras on the core and through the HTTP transport. The name census holds that the
  parameters are read nowhere; this holds what a client sees. (A review lane asked for it: a
  census proves the names unread, not the answer unchanged.)
  """
  use ExUnit.Case, async: true

  import Plug.Test, only: [conn: 3]
  import Plug.Conn, only: [put_req_header: 3]

  alias BeamMCP.{PromptSpec, ResourceSpec, Server, ToolSpec}
  alias BeamMCP.Transport.HTTP

  @modern "2026-07-28"
  @legacy "2025-11-25"
  @vkey "io.modelcontextprotocol/protocolVersion"

  defmodule Small do
    @behaviour BeamMCP.Catalog
    @impl true
    def capabilities do
      %{
        tools: [%ToolSpec{name: :t, command_class: :observe, mode: :read_only, description: "t"}],
        resources: [%ResourceSpec{uri: "s://one", name: "one"}],
        prompts: [%PromptSpec{name: "p"}]
      }
    end

    @impl true
    def read_resource("s://one"), do: {:ok, [%{uri: "s://one", text: "one"}]}
    @impl true
    def get_prompt("p", _), do: {:ok, %{messages: [%{role: :user, text: "p"}]}}
  end

  @continuation %{
    "inputResponses" => [%{"id" => "x", "value" => "y"}],
    "requestState" => "opaque"
  }

  @requests [
    {"tools/call", %{"name" => "t", "arguments" => %{}}, "t"},
    {"resources/read", %{"uri" => "s://one"}, "s://one"},
    {"prompts/get", %{"name" => "p"}, "p"}
  ]

  defp message(method, params, version) do
    meta =
      if version == @modern,
        do: %{@vkey => @modern, "io.modelcontextprotocol/clientCapabilities" => %{}},
        else: %{@vkey => @legacy}

    %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => method,
      "params" => Map.put(params, "_meta", meta)
    }
  end

  defp with_continuation(msg), do: update_in(msg, ["params"], &Map.merge(&1, @continuation))

  test "on the core, at both eras, the answer with the continuation parameters is the bare answer" do
    state = Server.new(catalog: Small, dispatch: fn _, args, _ -> {:ok, args} end)

    for version <- [@modern, @legacy], {method, params, _} <- @requests do
      msg = message(method, params, version)
      {_, bare} = Server.handle_message(state, msg)
      {_, continued} = Server.handle_message(state, with_continuation(msg))
      assert Map.has_key?(bare, "result"), "#{method} at #{version} answered #{inspect(bare)}"
      assert continued == bare, "#{method} at #{version}"
      # Nothing of the continuation reached the answer.
      refute inspect(continued) =~ "opaque"
    end
  end

  test "through the HTTP transport the answer with the continuation parameters is the bare answer" do
    opts =
      HTTP.init(
        catalog: Small,
        dispatch: fn _, args, _ -> {:ok, args} end,
        authorize: fn _ -> :ok end,
        allowed_origins: :any
      )

    for {method, params, name} <- @requests do
      msg = message(method, params, @modern)

      post = fn body ->
        :post
        |> conn("/mcp", Jason.encode!(body))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("mcp-protocol-version", @modern)
        |> put_req_header("mcp-method", method)
        |> put_req_header("mcp-name", name)
        |> HTTP.call(opts)
      end

      bare = post.(msg)
      continued = post.(with_continuation(msg))
      assert bare.status == 200, method
      assert continued.status == 200, method
      assert Jason.decode!(continued.resp_body) == Jason.decode!(bare.resp_body), method
    end
  end
end
