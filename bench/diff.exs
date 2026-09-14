# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# The diff engine's cost on a 10 000-edge fixture, recorded each gate run.
#
#     mix run bench/diff.exs
#
# 501 nodes (a server and 500 tools) and up to 10 000 random edges per side over the four
# edge kinds, seeded, de-duplicated by key; `Diff.run/3` and `Diff.encode!/1` timed warm (one
# untimed run first). Prints one line. THIS STEP RECORDS AND DOES NOT JUDGE: no threshold
# has been set for the diff; until the owner sets one against these numbers it exits 0.
alias BeamMCP.Connectome.{Diff, Edge, Graph, Node}

server = "bench"
srv = Node.new!(kind: :server, level: :server, identity: {:server, server})

tools =
  for i <- 1..500, do: Node.new!(kind: :tool, level: :server, identity: {:tool, server, :"t#{i}"})

id = fn i -> Node.id({:tool, server, :"t#{i}"}) end

edges = fn provenance, seed ->
  :rand.seed(:exsss, seed)

  for _ <- 1..10_000 do
    Edge.new!(
      from: id.(:rand.uniform(500)),
      to: id.(:rand.uniform(500)),
      kind: Enum.random([:invoke, :read, :message, :supervise]),
      provenance: provenance
    )
  end
  |> Enum.uniq_by(&Edge.key/1)
end

declared =
  Graph.new!(
    schema_version: Graph.schema_version(),
    nodes: [srv | tools],
    edges: edges.(:declared, {1, 2, 3})
  )

observed =
  Graph.new!(
    schema_version: Graph.schema_version(),
    nodes: [srv | tools],
    edges: edges.(:observed, {1, 2, 4})
  )

window = %{"started_at" => "2026-09-14T00:00:00Z", "ended_at" => "2026-09-14T01:00:00Z"}

{:ok, _} = Diff.run(declared, observed, window: window)
{run_us, {:ok, diff}} = :timer.tc(fn -> Diff.run(declared, observed, window: window) end)
{encode_us, bytes} = :timer.tc(fn -> Diff.encode!(diff) end)

IO.puts(
  "diff #{length(declared.edges)}/#{length(observed.edges)} edges: run #{div(run_us, 1000)} ms, " <>
    "encode #{div(encode_us, 1000)} ms, record #{byte_size(bytes)} B (recorded, no threshold set)"
)
