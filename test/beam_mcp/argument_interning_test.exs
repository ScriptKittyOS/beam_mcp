# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.ArgumentInterningTest do
  @moduledoc """
  A caller-supplied argument name interns nothing, on either path that takes arguments:
  `tools/call` and `prompts/get`. The atom table is one per VM and never garbage-collected,
  so a server that made an atom of a caller's key could be filled up by a caller; both paths
  refuse an undeclared key by schema and normalise only the declared ones. Measured over
  10,000 distinct keys, not assumed -- the tools path's bound had been stated and never
  written as a test. `async: false`, because the counter is the whole VM's: concurrent test
  modules define modules and intern atoms of their own, and did (measured: +154 in a run
  alongside the rest of the suite).
  """
  use ExUnit.Case, async: false

  alias BeamMCP.{Catalog, PromptArgument, PromptSpec, Server}

  @modern %{
    "io.modelcontextprotocol/protocolVersion" => "2026-07-28",
    "io.modelcontextprotocol/clientCapabilities" => %{}
  }

  defmodule Keyed do
    @behaviour Catalog

    @impl true
    def capabilities do
      %{
        tools: [
          %BeamMCP.ToolSpec{
            name: :t,
            command_class: :observe,
            mode: :read_only,
            description: "t",
            input_schema: %{"type" => "object", "properties" => %{"k" => %{"type" => "string"}}}
          }
        ],
        resources: [],
        prompts: [%PromptSpec{name: "p", arguments: [%PromptArgument{name: "k"}]}]
      }
    end

    @impl true
    def get_prompt("p", _args), do: {:ok, %{messages: []}}
  end

  defp call(state, method, params) do
    {_, r} =
      Server.handle_message(state, %{
        "jsonrpc" => "2.0",
        "id" => 7,
        "method" => method,
        "params" => Map.put(params, "_meta", @modern)
      })

    r
  end

  test "10,000 distinct caller keys through prompts/get and tools/call leave the atom table where it was" do
    s = Server.new(catalog: Keyed, dispatch: fn _, _, _ -> {:ok, "ok"} end)
    # Warm both paths once so any lazy interning of the package's own names is behind us.
    call(s, "prompts/get", %{"name" => "p", "arguments" => %{"k" => "v"}})
    call(s, "tools/call", %{"name" => "t", "arguments" => %{"k" => "v"}})
    before = :erlang.system_info(:atom_count)

    for i <- 1..10_000 do
      key = "caller-key-#{i}-#{System.unique_integer([:positive])}"
      call(s, "prompts/get", %{"name" => "p", "arguments" => %{key => "v"}})
      call(s, "tools/call", %{"name" => "t", "arguments" => %{key => "v"}})
    end

    assert :erlang.system_info(:atom_count) == before
  end
end
