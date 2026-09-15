<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Reachability: what an entry can reach, and what it must cross to get there

`BeamMCP.Connectome.Reach` answers four questions about a `BeamMCP.Connectome.Graph` — the
declared graph is the point, since it says what *can* happen. This page is the contract: the
definitions, what an answer carries, what each question costs, and what is refused. A
consumer can check every answer against the graph it handed in, because the graph is the
only input and a witness is made of the graph's own edges.

## The four questions

| function | question | answer |
| -- | -- | -- |
| `BeamMCP.Connectome.Reach.reachable?/4` | is there a path from `from` to `to`? | `{:ok, true \| false}` |
| `BeamMCP.Connectome.Reach.reachable_without/5` | is there a path from `from` to `to` that crosses none of the `gates`? | `{:ok, false}`, or `{:ok, %Path{}}` — the witness |
| `BeamMCP.Connectome.Reach.dominates?/4` | does every path from the entry set to `target` pass `gate`? | `{:ok, true \| false}` |
| `BeamMCP.Connectome.Reach.mandatory_pass/3` | which nodes does every path from the entry set to `target` cross? | `{:ok, MapSet}` — the dominators of `target`, itself excluded |

A **path** is a sequence of the graph's edges, each edge's `to` the next edge's `from`,
following edges in their direction. A path from a node to itself is the empty path, zero
hops — a node reaches itself whether or not a cycle passes through it. **Crossing** a node
means the node is on the path, at either end or between: `reachable_without/5` answers
`{:ok, false}` when `from` or `to` is itself a gate.

The **entry set** is the graph's server nodes (`kind: :server`) unless `entries:` names
other node ids. Every question about "the entry set" is asked from a virtual root with an
edge to each entry, so the set is one source. A node that is an entry is on every path only
when it is the sole entry: with two entries, neither dominates what both reach. That is what
the definition says, and the answers follow it rather than a reader's intuition that "the
server is always crossed".

## The witness

`reachable_without/5` returns `%BeamMCP.Connectome.Reach.Path{nodes: [...], edges: [...]}`:
`nodes` from `from` to `to` in order, `edges` one input edge per step — the first edge in the
graph's edge order (canonical, for a graph `BeamMCP.Connectome.Graph.new/1` built) between the
two nodes whose kind the query admitted — so
`length(edges) == length(nodes) - 1`, every edge is `in graph.edges`, each consecutive pair of
nodes is that edge's `from` and `to`, and no gate is among the nodes. A property test holds
all four over generated graphs. The witness is a **shortest** gate-free path in hops among
the admitted kinds; when several are shortest, the one breadth-first search finds first.
The witness is a path in the **input** graph at the level the graph was built at — a module
graph's witness names modules, never a collapsed group.

## Constraints — each scoped to the questions it bears on

- `kinds:` (every query) — the edge kinds the search may follow, a non-empty subset of the
  vocabulary's four (`docs/connectome.md`); default all four. An edge of another kind is not
  there.
- `max_hops:` (`reachable?/4` and `reachable_without/5` only) — a positive integer or
  `:infinity` (default). A shortest path longer than it is not a path for the question asked:
  `reachable?/4` answers `false`, `reachable_without/5` answers `{:ok, false}`. `max_hops: 1`
  is adjacency.
- `entries:` (`dominates?/4` and `mandatory_pass/3` only) — the entry set; a non-empty list
  of node ids the graph holds. Without it, the server nodes; a graph with none is refused
  (`{:invalid, :entries, []}`), never answered "unreachable".
- `max_edges:` (every query) — see below.

**An option that cannot bear on the question asked is refused by name**
(`{:error, {:unknown_option, key}}`), not read. A review found that with `max_hops:` read by
`dominates?/4` the module could hand back a gate-free witness round a node and, in the same
breath, call that node a dominator, and the two dominance implementations disagreed.
Bounded-length dominance is a different question from the one Lengauer–Tarjan answers, and
it is not offered.

**Signs are not consulted.** An edge's `sign` is the host's (`docs/connectome.md`); the
package writes `:unset` and reads none of them here. "Avoid these nodes" is the whole of
the sign-aware question this release answers; reachability that reads `:deny` off an edge
waits for a consumer that populates signs.

## Dominance, defined and implemented twice

`gate` **dominates** `target` from the entry set when every path from the virtual root to
`target` passes `gate`. Two implementations answer it, and a property holds them to each
other on every node of generated graphs:

- `dominates?/4` is the definition itself: `target` is reachable from the root with `gate`
  present, and unreachable with `gate` and its edges removed. Two searches.
- `mandatory_pass/3` is Lengauer–Tarjan (1979), the simple variant with path compression,
  over the part of the graph the root reaches — one build; the algorithm's own depth-first
  numbering is what says the target is unreachable — returning the chain of immediate
  dominators above `target` with the root and `target` left out. OTP's `:digraph_utils` has
  no dominator function (measured on OTP 28), so it is written in the package and held to
  `dominates?/4` — by the property, and by two independent oracles a review lane wrote from
  this page's definition (all simple paths intersected; node removal), which agreed with
  both functions on every target and gate of 1 200 random graphs.

When `target` is unreachable from the entry set both answer `{:error, {:unreachable, target}}`:
dominance is undefined there, and `true` would make an unreachable effect look guarded.
`dominates?(g, x, x)` is `{:ok, true}` when `x` is reachable — every path to `x` passes `x`.

## What it costs

Every query checks the graph (`BeamMCP.Connectome.Graph.check/1`, O(V + E)) and builds a
private `:digraph` from it — O(V + E), the edges filtered to `kinds:` and the removed nodes
left out — and deletes it when the query returns, on every exit. On top of that:

| function | work | bound |
| -- | -- | -- |
| `reachable?/4` | one breadth-first search | O(V + E) |
| `reachable_without/5` | one breadth-first search, then the admitted edges indexed once by `{from, to}` and the path's edges read from the index | O(V + E) |
| `dominates?/4` | two builds, two searches | O(V + E) |
| `mandatory_pass/3` | one build, a depth-first numbering, Lengauer–Tarjan | O(E log V) in the paper's array model; O(E log² V) here, the state being immutable maps |

Measured on the gate's 10 000-edge fixture (501 nodes, ~9 970 edges after de-duplication,
32 schedulers, OTP 28; medians of five after a warm-up, `bench/reach.exs`, recorded by every
gate run and judged by nothing): a search ~14–21 ms across this machine's runs, of which the graph check and the
`:digraph` build are most; `dominates?/4` ~24 ms; `mandatory_pass/3` ~22 ms. (Before the
review added the graph check and removed a second build from `mandatory_pass/3`: ~11, ~21 and
~30.) No threshold is set for graph cost — that is the owner's, against these numbers.

## Refused, by name

- `max_edges:` (default 1 000 000): a graph with more edges is refused as
  `{:error, {:cap, :max_edges, n}}` before any table is built. It is the one cap, on the
  one thing that costs memory.
- `all_paths/4` is `{:error, {:refused, :all_paths}}`, always. The number of paths between
  two nodes is exponential in the graph, and no cap makes enumerating them a question this
  package should answer — a cap on that would be raised until it meant nothing. Motif
  isomorphism is not offered for the same reason. That is the boundary: what is cheap on the
  BEAM — searches and dominators — is here; what is not is refused rather than attempted.
- An unknown option, or one the question cannot use (`{:unknown_option, key}`), an option of
  the wrong shape (`{:invalid, key, value}`), an edge kind outside the vocabulary, an empty
  entry set, and a node id — as `from`, `to`, a gate, an entry or a target — the graph does
  not hold (`{:unknown_node, id}`) are each refused by name, before anything is built. The
  order, when more than one applies: the options first (an entry id the graph does not hold
  is an option fault, found here), then the edge cap, then the graph check, then the ids
  given as arguments — so a graph over the cap is refused as over the cap whatever else is
  wrong with the call, and the O(V + E) check never runs on a graph the cap refuses.
- A graph `BeamMCP.Connectome.Graph.check/1` would refuse — a literal `%Graph{}` with a
  dangling edge, a struct of the wrong shape — is refused as `{:error, {:invalid_graph,
  reason}}` with that function's reason, never answered: `:digraph` would drop the dangling
  edge without a word and the answer would describe a graph nobody handed in.

## Worked example

The gate fixture: a server `srv`, tools `a`, `b`, `g`, `x`, and edges `srv→a`, `srv→b`,
`a→g`, `b→g`, `g→x`, all `:invoke`. The only way to `x` is through `g`.

    reachable?(graph, "srv/server", "srv/tool/x")                    → {:ok, true}
    dominates?(graph, "srv/tool/g", "srv/tool/x")                     → {:ok, true}
    reachable_without(graph, "srv/server", "srv/tool/x", ["srv/tool/g"]) → {:ok, false}
    mandatory_pass(graph, "srv/tool/x")                                → {:ok, #MapSet<["srv/server", "srv/tool/g"]>}

Add the bypass `a→x`:

    reachable_without(graph, "srv/server", "srv/tool/x", ["srv/tool/g"])
      → {:ok, %Path{nodes: ["srv/server", "srv/tool/a", "srv/tool/x"], edges: [srv→a, a→x]}}
    dominates?(graph, "srv/tool/g", "srv/tool/x")                     → {:ok, false}
    mandatory_pass(graph, "srv/tool/x")                                → {:ok, #MapSet<["srv/server"]>}

Neither `a` nor `b` dominates `x` in either graph: each has the other as a way round.

## What this does not do

It does not read signs; it does not replay an observed graph over a declared one (effective
connectivity is a later release); it does not enumerate paths or match motifs; it does not
cache — every query is a fresh build over the graph it is handed, so a graph that changed
between two calls gives two honest answers and no stale one.
