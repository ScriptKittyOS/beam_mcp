# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.RequestContextTest do
  @moduledoc """
  The request's context reaches the host's dispatch under the reserved `:mcp` key of its third
  argument: the request's `params._meta` as the client sent it, the client's capabilities and
  the protocol revision the request is served under.

  Before, the third argument was the host's static `dispatch_opts` and nothing else: the core
  stripped `params._meta` before `tools/call` was matched, and kept no client capabilities, so
  a host that needed a trace id, a progress token or a capability the client declared could
  not see it, and the next protocol addition that rides in `_meta` would have needed a new
  function. One reserved key carries all of it, and later fields join that map.
  """
  use ExUnit.Case, async: true

  alias BeamMCP.Server
  alias BeamMCP.Transport.HTTP

  @modern "2026-07-28"
  @legacy "2025-11-25"
  @vkey "io.modelcontextprotocol/protocolVersion"
  @ckey "io.modelcontextprotocol/clientCapabilities"

  defmodule Catalog do
    @moduledoc false
    def capabilities do
      %{
        tools: [
          %BeamMCP.ToolSpec{
            name: :probe,
            command_class: :observe,
            mode: :read_only,
            description: "Reports what dispatch was handed."
          }
        ],
        resources: [],
        prompts: []
      }
    end
  end

  defp server(extra \\ []) do
    parent = self()

    Server.new(
      [
        catalog: Catalog,
        dispatch: fn _tool, _args, opts ->
          send(parent, {:dispatched, opts})
          {:ok, %{}}
        end,
        dispatch_opts: [host: :own]
      ] ++ extra
    )
  end

  defp call(state, id, meta) do
    params = %{"name" => "probe", "arguments" => %{}}
    params = if meta, do: Map.put(params, "_meta", meta), else: params

    Server.handle_message(state, %{
      "jsonrpc" => "2.0",
      "id" => id,
      "method" => "tools/call",
      "params" => params
    })
  end

  test "a modern request's _meta, capabilities and revision reach dispatch under :mcp" do
    caps = %{"elicitation" => %{}}
    meta = %{@vkey => @modern, @ckey => caps, "com.example/trace" => "t-1"}

    {_state, response} = call(server(), 1, meta)
    assert %{"result" => _} = response
    assert_receive {:dispatched, opts}

    assert opts[:host] == :own
    assert opts[:mcp] == %{meta: meta, client_capabilities: caps, protocol_version: @modern}
  end

  test "one request's _meta never reaches the next request's dispatch" do
    {state, _} =
      call(server(), 1, %{@vkey => @modern, @ckey => %{}, "com.example/trace" => "t-1"})

    assert_receive {:dispatched, _}

    # A request with no _meta at all is the one a leak would reach: nothing of its own to
    # overwrite the last request's.
    {_state, _} = call(state, 2, nil)
    assert_receive {:dispatched, opts}
    assert opts[:mcp].meta == %{}
  end

  test "a legacy session's capabilities and revision come from initialize; a request without _meta has %{}" do
    caps = %{"roots" => %{"listChanged" => true}}

    {state, _} =
      Server.handle_message(server(), %{
        "jsonrpc" => "2.0",
        "id" => 0,
        "method" => "initialize",
        "params" => %{"protocolVersion" => @legacy, "capabilities" => caps}
      })

    {_state, _} = call(state, 1, nil)
    assert_receive {:dispatched, opts}
    assert opts[:mcp] == %{meta: %{}, client_capabilities: caps, protocol_version: @legacy}
  end

  test "a request without _meta is told the revision it is served under, whatever initialize negotiated" do
    # initialize may name 2026-07-28, but a request without _meta never reaches the versioned
    # clause: it is answered legacy-shaped (no resultType), so 2025-11-25 is its revision.
    {state, _} =
      Server.handle_message(server(), %{
        "jsonrpc" => "2.0",
        "id" => 0,
        "method" => "initialize",
        "params" => %{"protocolVersion" => @modern, "capabilities" => %{}}
      })

    {_state, response} = call(state, 1, nil)
    refute Map.has_key?(response["result"], "resultType")
    assert_receive {:dispatched, opts}
    assert opts[:mcp].protocol_version == @legacy
  end

  test "a capabilities value that is not an object reaches dispatch as nil" do
    {_state, _} = call(server(), 1, %{@vkey => @modern, @ckey => "x"})
    assert_receive {:dispatched, opts}
    assert opts[:mcp].client_capabilities == nil
  end

  test "a state without the request field (built by hand, or held from before it existed) is served" do
    state = Map.delete(server(), :request)
    {_state, response} = call(state, 1, %{@vkey => @modern, @ckey => %{}})
    assert %{"result" => _} = response
  end

  test "over HTTP, where every request builds a fresh state, the context arrives the same way" do
    parent = self()
    meta = %{@vkey => @modern, @ckey => %{"sampling" => %{}}, "com.example/trace" => "t-9"}

    opts =
      HTTP.init(
        catalog: Catalog,
        dispatch: fn _t, _a, o ->
          send(parent, {:dispatched, o})
          {:ok, %{}}
        end,
        authorize: fn _conn -> :ok end,
        allowed_origins: :any
      )

    body = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "tools/call",
      "params" => %{"name" => "probe", "arguments" => %{}, "_meta" => meta}
    }

    conn =
      Plug.Test.conn(:post, "/mcp", Jason.encode!(body))
      |> Plug.Conn.put_req_header("content-type", "application/json")
      |> Plug.Conn.put_req_header("mcp-protocol-version", @modern)
      |> Plug.Conn.put_req_header("mcp-method", "tools/call")
      |> Plug.Conn.put_req_header("mcp-name", "probe")
      |> HTTP.call(opts)

    assert conn.status == 200
    assert_receive {:dispatched, o}

    assert o[:mcp] == %{
             meta: meta,
             client_capabilities: %{"sampling" => %{}},
             protocol_version: @modern
           }
  end

  test "a host's own :mcp key is refused by new/1, and by the HTTP transport at init: the key is reserved" do
    assert_raise ArgumentError, ~r/:dispatch_opts.*:mcp/s, fn ->
      Server.new(catalog: Catalog, dispatch_opts: [mcp: :mine])
    end

    assert_raise ArgumentError, ~r/:dispatch_opts.*:mcp/s, fn ->
      HTTP.init(
        catalog: Catalog,
        authorize: fn _ -> :ok end,
        allowed_origins: :any,
        dispatch_opts: [mcp: :mine]
      )
    end
  end
end
