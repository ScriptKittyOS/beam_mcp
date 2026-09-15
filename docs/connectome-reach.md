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
graph's canonical order between the two nodes whose kind the query admitted — so
`length(edges) == length(nodes) - 1`, every edge is `in graph.edges`, each consecutive pair of
nodes is that edge's `from` and `to`, and no gate is among the nodes. A property test holds
all four over generated graphs. The witness is a **shortest** gate-free path in hops among
the admitted kinds; when several are shortest, the one breadth-first search finds first.
The witness is a path in the **input** graph at the level the graph was built at — a module
graph's witness names modules, never a collapsed group.

## Constraints

- `kinds:` — the edge kinds the search may follow, a non-empty subset of the vocabulary's
  four (`docs/connectome.md`); default all four. An edge of another kind is not there.
- `max_hops:` — a positive integer or `:infinity` (default). A shortest path longer than it
  is not a path for the question asked: `reachable?/4` answers `false`, `reachable_without/5`
  answers `{:ok, false}`. `max_hops: 1` is adjacency.
- `entries:` — the entry set for `dominates?/4` and `mandatory_pass/3`; a non-empty list of
  node ids the graph holds.

**Signs are not consulted.** An edge's `sign` is the host's (`docs/connectome.md`); the
package writes `:unknown` and reads none of them here. "Avoid these nodes" is the whole of
the sign-aware question this release answers; reachability that reads `:deny` off an edge
waits for a consumer that populates signs.

## Dominance, defined and implemented twice

`gate` **dominates** `target` from the entry set when every path from the virtual root to
`target` passes `gate`. Two implementations answer it, and a property holds them to each
other on every node of generated graphs:

- `dominates?/4` is the definition itself: `target` is reachable from the root with `gate`
  present, and unreachable with `gate` and its edges removed. Two searches.
- `mandatory_pass/3` is Lengauer–Tarjan (1979), the simple variant with path compression,
  over the part of the graph the root reaches, returning the chain of immediate dominators
  above `target` with the root and `target` left out. OTP's `:digraph_utils` has no dominator
  function (measured on OTP 28), so it is written in the package and held to `dominates?/4`.

When `target` is unreachable from the entry set both answer `{:error, {:unreachable, target}}`:
dominance is undefined there, and `true` would make an unreachable effect look guarded.
`dominates?(g, x, x)` is `{:ok, true}` when `x` is reachable — every path to `x` passes `x`.

## What it costs

Every query builds a private `:digraph` from the graph — O(V + E) in the graph's size, the
edges filtered to `kinds:` and the removed nodes left out — and deletes it when the query
returns, on every exit. On top of that:

| function | work | bound |
| -- | -- | -- |
| `reachable?/4` | one breadth-first search | O(V + E) |
| `reachable_without/5` | one breadth-first search, then the edges of the path resolved against the graph's edge list | O(V + E + hops · E) |
| `dominates?/4` | two builds, two searches | O(V + E) |
| `mandatory_pass/3` | one build, a depth-first numbering, Lengauer–Tarjan | O(E log V) |

Measured on the gate's 10 000-edge fixture (501 nodes, ~9 970 edges after de-duplication,
32 schedulers, OTP 28; medians of five after a warm-up, `bench/reach.exs`, recorded by every
gate run and judged by nothing): a search ~11 ms, of which the `:digraph` build is most;
`dominates?/4` ~21 ms; `mandatory_pass/3` ~30 ms. No threshold is set for graph cost — that
is the owner's, against these numbers.

## Refused, by name

- `max_edges:` (default 1 000 000): a graph with more edges is refused as
  `{:error, {:cap, :max_edges, n}}` before any table is built. It is the one cap, on the
  one thing that costs memory.
- `all_paths/4` is `{:error, {:refused, :all_paths}}`, always. The number of paths between
  two nodes is exponential in the graph, and no cap makes enumerating them a question this
  package should answer — a cap on that would be raised until it meant nothing. Motif
  isomorphism is not offered for the same reason. That is the boundary: what is cheap on the
  BEAM — searches and dominators — is here; what is not is refused rather than attempted.
- An unknown option (`{:unknown_option, key}`), an option of the wrong shape
  (`{:invalid, key, value}`), an edge kind outside the vocabulary, and a node id — as `from`,
  `to`, a gate, an entry or a target — the graph does not hold (`{:unknown_node, id}`) are each
  refused by name, before anything is built.

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
