# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.InjectionTest do
  @moduledoc """
  The injected catalog governs both `tools/list` and `tools/call`.

  Demonstrated red in the source tree before extraction: `tools/list` advertised a tool from
  the injected catalog while `tools/call` on that same tool never reached dispatch, because
  the name check consulted a hardcoded catalog instead of the injected one.
  """
  use ExUnit.Case, async: true

  alias BeamMCP.Server

  defmodule CatalogWithNovelTool do
    @behaviour BeamMCP.ToolCatalog

    @impl true
    def all do
      [
        %BeamMCP.ToolSpec{
          name: :novel_tool,
          command_class: :observe,
          mode: :read_only,
          description: "A tool no hardcoded catalog knows about."
        }
      ]
    end
  end

  test "an injected catalog's tool is advertised by tools/list" do
    state = Server.new(tool_catalog: CatalogWithNovelTool)

    {_s, resp} =
      Server.handle_message(state, %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"})

    assert Enum.map(resp["result"]["tools"], & &1["name"]) == ["novel_tool"]
  end

  test "tools/call on that same injected tool reaches dispatch" do
    parent = self()

    dispatch = fn name, args, opts ->
      send(parent, {:dispatch, name, args, opts})
      {:ok, %{}}
    end

    state = Server.new(dispatch: dispatch, tool_catalog: CatalogWithNovelTool)

    {_s, resp} =
      Server.handle_message(state, %{
        "jsonrpc" => "2.0",
        "id" => 2,
        "method" => "tools/call",
        "params" => %{"name" => "novel_tool", "arguments" => %{}}
      })

    assert_receive {:dispatch, :novel_tool, _args, _opts}, 200
    refute resp["error"]
  end
end
