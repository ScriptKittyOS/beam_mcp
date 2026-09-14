# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.ServerTest do
  use ExUnit.Case, async: true

  alias BeamMCP.Server

  defmodule FakeCatalog do
    def capabilities, do: %{tools: all_tools(), resources: [], prompts: []}

    defp all_tools do
      [
        %BeamMCP.ToolSpec{
          name: :get_latest_alerts,
          command_class: :observe,
          mode: :read_only,
          description: "Read the latest alert queue entries."
        },
        %BeamMCP.ToolSpec{
          name: :propose_action,
          command_class: :contain,
          mode: :proposal,
          description: "Propose an approval-governed action request.",
          input_schema: %{
            "type" => "object",
            "properties" => %{
              "case_id" => %{"type" => "string"},
              "action_class" => %{"type" => "string"},
              "target" => %{"type" => "string"}
            },
            "required" => ["case_id", "action_class", "target"],
            "additionalProperties" => false
          }
        }
      ]
    end
  end

  describe "new/1 refuses a wrong option by name, at construction" do
    # Found by a review lane: `server_name` was held whatever it was, and a non-binary one
    # raised inside the connectome's id derivation at snapshot time, far from the call that
    # supplied it. The catalog was the only option validated. Every option `new/1` accepts
    # is now read the way the catalog is: refused at `new/1` with a message naming the key
    # and the shape it wanted, never guessed at.
    test "server_name must be a string" do
      for bad <- [:beam_mcp, ~c"beam_mcp", 1, nil] do
        assert_raise ArgumentError, ~r/:server_name/, fn ->
          Server.new(catalog: FakeCatalog, server_name: bad)
        end
      end

      assert %{server_name: "s"} = Server.new(catalog: FakeCatalog, server_name: "s")
    end

    test "dispatch, when given, must be a function of three arguments" do
      for bad <- [fn -> :ok end, fn _, _ -> :ok end, :dispatch, &Function.identity/1] do
        assert_raise ArgumentError, ~r/:dispatch/, fn ->
          Server.new(catalog: FakeCatalog, dispatch: bad)
        end
      end

      # Absent is allowed: a server that serves no tools/call needs none.
      assert %{dispatch: nil} = Server.new(catalog: FakeCatalog)
    end

    test "dispatch_opts must be a keyword list" do
      for bad <- [%{a: 1}, [1, 2], "opts"] do
        assert_raise ArgumentError, ~r/:dispatch_opts/, fn ->
          Server.new(catalog: FakeCatalog, dispatch_opts: bad)
        end
      end

      assert %{dispatch_opts: [a: 1]} = Server.new(catalog: FakeCatalog, dispatch_opts: [a: 1])
    end

    test "tools_ttl_ms must be a non-negative integer, tools_cache_scope a string" do
      for bad <- [-1, 1.5, "0", nil] do
        assert_raise ArgumentError, ~r/:tools_ttl_ms/, fn ->
          Server.new(catalog: FakeCatalog, tools_ttl_ms: bad)
        end
      end

      for bad <- [:public, 1, nil] do
        assert_raise ArgumentError, ~r/:tools_cache_scope/, fn ->
          Server.new(catalog: FakeCatalog, tools_cache_scope: bad)
        end
      end

      assert %{tools_ttl_ms: 0, tools_cache_scope: "public"} =
               Server.new(catalog: FakeCatalog, tools_ttl_ms: 0, tools_cache_scope: "public")
    end

    test "the options must be a keyword list at all" do
      assert_raise ArgumentError, ~r/keyword list/, fn -> Server.new(%{catalog: FakeCatalog}) end
    end

    test "an option new/1 does not accept is refused by name too" do
      assert_raise ArgumentError, ~r/:server_nam\b/, fn ->
        Server.new(catalog: FakeCatalog, server_nam: "typo")
      end
    end
  end

  test "initialize advertises MCP tool capability" do
    state = Server.new(catalog: FakeCatalog)

    {next_state, response} =
      Server.handle_message(state, %{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize"})

    assert next_state.initialized?
    # The supported set is 2026-07-28 + 2025-11-25. An initialize with no requested version
    # gets the newest legacy revision; 2024-11-05 is no longer offered.
    assert response["result"]["protocolVersion"] == "2025-11-25"
    assert response["result"]["capabilities"] == %{"tools" => %{"listChanged" => false}}
    assert response["result"]["serverInfo"]["name"] == "beam_mcp"
  end

  test "tools/list exposes MCP-compatible tool metadata" do
    state = Server.new(catalog: FakeCatalog)

    {_next_state, response} =
      Server.handle_message(state, %{"jsonrpc" => "2.0", "id" => 2, "method" => "tools/list"})

    assert %{"result" => %{"tools" => tools}} = response
    assert Enum.map(tools, & &1["name"]) == ["get_latest_alerts", "propose_action"]

    proposal_tool = Enum.find(tools, &(&1["name"] == "propose_action"))
    assert proposal_tool["annotations"]["destructiveHint"]
    assert proposal_tool["inputSchema"]["required"] == ["case_id", "action_class", "target"]
  end

  test "tools/call normalizes JSON arguments before dispatching" do
    parent = self()

    dispatch = fn name, args, opts ->
      send(parent, {:dispatch, name, args, opts})
      {:ok, %{received: args[:action_class], case_id: args[:case_id], target: args[:target]}}
    end

    state = Server.new(dispatch: dispatch, catalog: FakeCatalog)

    {_next_state, response} =
      Server.handle_message(state, %{
        "jsonrpc" => "2.0",
        "id" => 3,
        "method" => "tools/call",
        "params" => %{
          "name" => "propose_action",
          "arguments" => %{
            "case_id" => "case-7",
            "action_class" => "contain",
            "target" => "host-42"
          }
        }
      })

    assert_receive {:dispatch, :propose_action, args, []}
    assert args[:case_id] == "case-7"
    # The package normalises the KEY and passes the VALUE through. Turning "contain" into an
    # atom is domain knowledge and belongs to the host's dispatch, not to a generic server.
    assert args[:action_class] == "contain"
    assert args[:target] == "host-42"

    assert response["result"]["isError"] == false

    assert response["result"]["structuredContent"] == %{
             "received" => "contain",
             "case_id" => "case-7",
             "target" => "host-42"
           }
  end

  test "unknown tools return a JSON-RPC error" do
    state = Server.new(catalog: FakeCatalog)

    {_next_state, response} =
      Server.handle_message(state, %{
        "jsonrpc" => "2.0",
        "id" => 4,
        "method" => "tools/call",
        "params" => %{"name" => "nope", "arguments" => %{}}
      })

    assert response["error"]["code"] == -32_601
    assert response["error"]["message"] == "Unknown tool: nope"
  end
end
