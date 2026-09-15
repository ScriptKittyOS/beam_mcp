# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# The reachability queries' cost on a 10 000-edge fixture, recorded each gate run.
#
#     mix run bench/reach.exs            (R=5 rounds by default; env R overrides)
#
# Built the way bench/overhead.exs is built and bench/diff.exs was not: one warm-up run of
# each query first, then R timed rounds, the MEDIAN reported. The fixture is bench/diff.exs's
# declared side -- a server, 500 tools, up to 10 000 random edges over the four kinds, seeded
# -- with the server wired into it (bench/diff.exs leaves the server node unconnected; a
# reachability fixture needs an entry that reaches something). Four queries, each including
# the private :digraph build the query makes and deletes: reachable? server -> t1;
# reachable_without server -> t1 avoiding twenty gates; dominates? t2 over t1; mandatory_pass
# of t1 (Lengauer-Tarjan over everything the entry reaches).
#
# RECORDS AND JUDGES NOTHING. No threshold has been set for graph cost (G-040: the owner's
# answer was to leave the diff recording and revisit when reachability made graph cost a
# thing a consumer feels -- this script is that measurement, brought to the owner). Prints one
# line; exits 0 unless a query fails outright.

alias BeamMCP.Connectome.{Edge, Graph, Node, Reach}

server = "bench"
srv = Node.new!(kind: :server, level: :server, identity: {:server, server})

tools =
  for i <- 1..500, do: Node.new!(kind: :tool, level: :server, identity: {:tool, server, :"t#{i}"})

id = fn i -> Node.id({:tool, server, :"t#{i}"}) end

:rand.seed(:exsss, {1, 2, 3})

random =
  for _ <- 1..10_000 do
    Edge.new!(
      from: id.(:rand.uniform(500)),
      to: id.(:rand.uniform(500)),
      kind: Enum.random([:invoke, :read, :message, :supervise]),
      provenance: :declared
    )
  end

# The server reaches the first ten tools directly; everything else is reached, or not, through
# the random edges. Duplicate keys are dropped as bench/diff.exs drops them.
entry_edges =
  for i <- 1..10,
      do:
        Edge.new!(
          from: Node.id({:server, server}),
          to: id.(i),
          kind: :invoke,
          provenance: :declared
        )

graph =
  Graph.new!(
    schema_version: Graph.schema_version(),
    nodes: [srv | tools],
    edges: Enum.uniq_by(entry_edges ++ random, &Edge.key/1)
  )

rounds = String.to_integer(System.get_env("R", "5"))
srv_id = Node.id({:server, server})
gates = Enum.map(11..30, id)

queries = [
  {"reachable?", fn -> Reach.reachable?(graph, srv_id, id.(1)) end},
  {"reachable_without(20 gates)",
   fn -> Reach.reachable_without(graph, srv_id, id.(1), gates) end},
  {"dominates?", fn -> Reach.dominates?(graph, id.(2), id.(1)) end},
  {"mandatory_pass", fn -> Reach.mandatory_pass(graph, id.(1)) end}
]

median_ms = fn run ->
  # One warm-up, then the median of R.
  {:ok, _} = run.()
  times = for _ <- 1..rounds, do: :timer.tc(run) |> elem(0)
  med = times |> Enum.sort() |> Enum.at(div(rounds, 2))
  Float.round(med / 1000, 2)
end

figures = Enum.map(queries, fn {name, run} -> "#{name} #{median_ms.(run)} ms" end)

{:ok, reached} = Reach.mandatory_pass(graph, id.(1))

IO.puts(
  "reach #{length(graph.edges)} edges/#{length(graph.nodes)} nodes: " <>
    Enum.join(figures, ", ") <>
    " (medians of #{rounds} after a warm-up; mandatory_pass set size #{MapSet.size(reached)}; recorded, no threshold set)"
)
