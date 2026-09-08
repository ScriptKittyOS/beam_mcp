# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# The era probe used to measure this slice. Tracked so that logs/probe-after.txt is
# regenerable by anyone with the tree, like the other run-logs -- r1 round-3 finding 6.
#
#     mix run tools/probe_ping.exs > slices/001b-ping-guard/logs/probe-after.txt 2>&1

defmodule ProbeCatalog do
  @behaviour BeamMCP.Catalog
  @impl true
  def capabilities do
    tools = [
      %BeamMCP.ToolSpec{
        name: :echo,
        command_class: :observe,
        mode: :read_only,
        description: "Echo."
      }
    ]

    %{tools: tools, resources: [], prompts: []}
  end
end

state = BeamMCP.Server.new(catalog: ProbeCatalog, dispatch: fn _n, a, _o -> {:ok, a} end)
key = "io.modelcontextprotocol/protocolVersion"

send_one = fn label, msg ->
  {_s, r} = BeamMCP.Server.handle_message(state, msg)
  IO.puts("#{label}\n  -> #{Jason.encode!(r)}")
end

IO.puts("beam_mcp version: #{Mix.Project.config()[:version]}")
IO.puts("")

send_one.("ping + _meta 2026-07-28", %{
  "jsonrpc" => "2.0",
  "id" => 1,
  "method" => "ping",
  "_meta" => %{key => "2026-07-28"}
})

send_one.("ping + _meta 2025-11-25", %{
  "jsonrpc" => "2.0",
  "id" => 1,
  "method" => "ping",
  "_meta" => %{key => "2025-11-25"}
})

send_one.("ping + _meta, no version key", %{
  "jsonrpc" => "2.0",
  "id" => 1,
  "method" => "ping",
  "_meta" => %{"other" => 1}
})

send_one.("ping bare", %{"jsonrpc" => "2.0", "id" => 1, "method" => "ping"})

send_one.("tools/list + _meta 2025-11-25", %{
  "jsonrpc" => "2.0",
  "id" => 2,
  "method" => "tools/list",
  "_meta" => %{key => "2025-11-25"}
})

send_one.("tools/list + _meta 2026-07-28", %{
  "jsonrpc" => "2.0",
  "id" => 2,
  "method" => "tools/list",
  "_meta" => %{key => "2026-07-28"}
})
