<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# The connectome — vocabulary

A **connectome** is the wiring diagram of a composed MCP system: which parts exist, and what can
talk to what. It is a directed, typed graph, built before any message flows and again from what
actually ran, so the two can be compared.

This page fixes the words. The modules that carry them are `BeamMCP.Connectome.*`, added in the
releases that follow; every term a typespec there uses is defined here, and a test holds the two
together.

## What the package is and is not

beam_mcp renders authority; it never decides it. The connectome carries a sign slot so that a
graph can show what a policy allowed, denied or held — and the package itself writes only
`:unset` into that slot. It populates no sign, signs no finding, holds no key, and makes no
authority decision. Those belong to the host, behind the same `:authorize` and `:authorize_body`
hooks the transport already offers — where a host keeps its own risk tiers, approvals and
receipts, none of which this package holds. The connectome is not an MCP capability: neither protocol
revision this package targets defines a topology or a declared-reachability primitive, and none
is claimed.

## The names

- A **connectome** is the graph itself: nodes and edges, each edge carrying a kind, a sign and a
  provenance.
- The **declared connectome** is built from what is declared: the catalog's tools, resources and
  prompts, the static call graph between the host's modules, and the host's boundary declarations.
  It says what *can* happen.
- The **observed connectome** is built from what ran: telemetry on the dispatch path and, when the
  host opts in, a guarded tracer. It records edge identity only — never arguments, results or
  headers. It says what *did* happen, over a stated window.
- A **drift finding** is an edge the observed connectome has and the declared connectome does not,
  or an edge both have with a sign supplied on both sides and the two different (`unset` on
  either side is not a sign supplied: [`docs/connectome-diff.md`](connectome-diff.md)). Drift
  is a record; what to do about it is the host's.
- **Dead authority** is an edge the declared connectome has and the observed one never showed in the
  window. It is evidence the host can use to narrow what it declares; it is not a fault.
- A **coverage bound** is the measured fraction of one graph the other accounts for, stated with
  the window it was measured over. It is reported as a number, never assumed complete.
  `docs/connectome-diff.md` defines the classes and the counts the fractions are made from.

## Node kinds

| kind | what it is |
| -- | -- |
| `:server` | the MCP server: the thing whose catalog is advertised |
| `:tool` | a tool the catalog names; labelled with its `command_class` and `mode` |
| `:resource` | a resource the catalog names |
| `:prompt` | a prompt the catalog names |
| `:process` | a BEAM process — a GenServer, a task, a supervisor |
| `:module` | a BEAM module, at the module level, or a module–function–arity at the finest level |

## Edge kinds

| kind | what it is |
| -- | -- |
| `:invoke` | a call: a tool call from the server to a tool, a function call between modules |
| `:read` | a read of a resource or a prompt |
| `:message` | a message sent from one process to another |
| `:supervise` | an OTP supervision link from a supervisor to a child |

A tool dispatch is an `:invoke` edge whose source is the server node. There is no fifth kind for it.

## Sign

| sign | meaning |
| -- | -- |
| `:allow` | the host's policy permits this edge |
| `:deny` | the host's policy forbids it |
| `:hold` | the host's policy holds it for a decision it does not make alone — an advisory, never an approval |
| `:ungoverned` | a consumer looked and no gate — no rule of its policy, not a gate node of the reach page — applies to this edge: an affirmative statement, a supplied value like the three above; never a reason for the package to leave the edge out of anything |
| `:unset` | no sign has been supplied to this package; **the only value the package itself ever writes** |

The sign is a *slot*. The package carries it so that a rendered graph can show a policy's verdict
beside each edge; a **consumer** fills it — the host that embeds this package, or any party
holding a graph it produced; the pages use the two words for the same role. Nothing in the
package computes one. There is no setter: a consumer writes the struct field
(`%{edge | sign: :deny}`) and rebuilds the graph from its parts —
`BeamMCP.Connectome.Graph.new(nodes: g.nodes, edges: signed, schema_version: 2)` — or lets
`BeamMCP.Connectome.Graph.check/1` or the encoder see it; each checks the value against the
vocabulary and refuses, never corrects, anything else. **The bytes carry no field saying which
consumer wrote a sign, or when**: the bytes' edge object is `from`, `to`, `kind`,
`provenance`, `sign` and nothing more (a weight travels in the sidecar), so a sign's author and
its time are the consumer's own record to keep, outside this package.

`:unset` says exactly one thing: that nothing was handed here. It does not say that no policy
exists, that none spoke, or that none was computed — a host whose authority plane denied an
edge, where that verdict never reached this package, gets `:unset` on that edge, and a graph
that read `:unset` as "no policy spoke" would be wrong about the world. That is why the value is
named for the slot's state and not for the world's. (Until 0.5.0 the value was `:unknown`,
glossed "no policy has spoken"; the rename is the correction, and the bytes carry
`schema_version` `2` from here so a reader knows which vocabulary applies —
[`docs/connectome-canonical.md`](connectome-canonical.md).)

There is no `:not_applicable` and no `:indeterminate`: nothing in the package can produce them,
no consumer exists that does, and a value nothing writes is dead vocabulary a later reader will
misuse. A sign means the same thing on a declared edge and on an observed one; the pair
(`provenance`, `sign`) carries the whole fact, and no third value is added to say which side it
came from: on a declared edge a sign is what a consumer wrote against the configuration; on an
observed edge it is what a consumer wrote against the run. **The package never treats any
sign as suppression** — `:ungoverned` included: the diff records the edge exactly as it records
any other (a sign appears in the diff record only in a changed-sign entry; every sign is in the
graph's own bytes), and whether to suppress a finding is a consumer's decision, made in a
system that can say who decided and when — which this record, carrying no author and no time
of decision (its window is the observation's, the consumer's input), is not. A sign is also
orthogonal to drift: an observed edge nobody declared is drift whatever its sign.

## Level

Nodes can be built at, and a graph collapsed to, one of four levels, coarsest last:

| level | granularity |
| -- | -- |
| `:mfa` | one function: module, name, arity |
| `:module` | one module |
| `:boundary` | one OTP application, or one declared boundary where the host declares them |
| `:server` | one MCP server |

The finest level a graph was built at is kept; collapsing is a view, and a path reported by a
query is a path in the graph as built.

## Identity

A node's id is derived from a structural identity, never from a counter. The first element
names the kind of part; the second is the server identity the host supplies; the rest names
the part within it.

| identity | node |
| -- | -- |
| `{:server, server}` | the server itself |
| `{:tool, server, name}` · `{:resource, server, name}` · `{:prompt, server, name}` · `{:process, server, name}` | a catalog part or a process, named within the server |
| `{:module, server, module}` | a module, at the `:module` level |
| `{:module, server, {module, function, arity}}` | one function, at the `:mfa` level |
| `{:boundary, server, source, name}` | a group of modules, at the `:boundary` level, with the source of the grouping named |

Two different things group modules, and both arrive as atoms, so a boundary identity says
which it is:

| source | the grouping |
| -- | -- |
| `:application` | an OTP application, named by its atom |
| `:boundary_module` | a declared boundary, named by its root module |

A boundary identity and the `:boundary` level imply each other; a bare module is a
module-level node and a module-function-arity is an `:mfa`-level node.

### The id string

`BeamMCP.Connectome.Node.id/1` is the one place an identity becomes an id, and this is what
it writes. The components are written the server first, then the identity's tag (its
first element: `boundary` for a boundary identity, whose node kind is `module`), then the
rest of the identity in order — not the tuple's order, which puts the tag first — each
escaped and then joined by `/`. Escaping is `%` to `%25` first, then `/` to `%2F`, applied to
every component, so a `/` inside a server name or a resource URI never reads as a separator.
An atom naming a kind or a source is written as its name; a module is written as Elixir
prints it (`inspect/1`: `Foo.Bar`, or `:erl_mod` for an Erlang module, and a module atom
that is not a plain identifier is quoted the way Elixir quotes it, `:"has space"`); a
function name as its atom's name; an arity as a decimal integer. Nothing is normalised here; NFC is applied by
the canonical form, not by the id.

| identity | id |
| -- | -- |
| `{:server, "srv"}` | `srv/server` |
| `{:tool, "srv", "écho"}` | `srv/tool/écho` |
| `{:resource, "srv", "r://a"}` | `srv/resource/r:%2F%2Fa` |
| `{:prompt, "a/b", "p%"}` | `a%2Fb/prompt/p%25` |
| `{:process, "srv", :worker}` | `srv/process/worker` |
| `{:module, "srv", Foo.Bar}` | `srv/module/Foo.Bar` |
| `{:module, "srv", :erl_mod}` | `srv/module/:erl_mod` |
| `{:module, "srv", :"has space"}` | `srv/module/:"has space"` |
| `{:module, "srv", {Foo.Bar, :run, 2}}` | `srv/module/Foo.Bar/run/2` |
| `{:boundary, "srv", :application, :beam_mcp}` | `srv/boundary/application/beam_mcp` |
| `{:boundary, "srv", :boundary_module, Foo}` | `srv/boundary/boundary_module/Foo` |

The escaping is not reversed by anything in this package: an id is compared, sorted and
hashed as bytes, never parsed back into its identity.

## Provenance

| provenance | which build produced the edge |
| -- | -- |
| `:declared` | the declared connectome |
| `:observed` | the observed connectome |

An edge carries exactly one provenance. Comparing the two graphs is how a drift finding is made.

## Algorithm

| algorithm | the digest the canonical bytes name and are hashed with |
| -- | -- |
| `:sha256` | SHA-256, the default indefinitely; 32 bytes, 64 hexadecimal characters |
| `:sha384` | SHA-384, by option; 48 bytes, 96 characters |
| `:sha512` | SHA-512, by option; 64 bytes, 128 characters |

A canonical envelope — the graph's and the diff record's — names one algorithm in its bytes,
and its hash is that digest over exactly those bytes; a verifier reads the name from the bytes
(`docs/connectome-canonical.md`, rule 9). The three are the whole list: the package refuses any
other name at the option, before a byte is written. The package holds no key and makes no
signature; which of the three a consumer accepts is the consumer's policy.

## Weight

An edge may carry a weight — an observed call count, a latency summary. Weights are measurements.
They are never part of the declared connectome's canonical bytes, so the hash of a declared
connectome is a claim about wiring and nothing else.
