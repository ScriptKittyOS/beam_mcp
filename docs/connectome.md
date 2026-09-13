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
`:unknown` into that slot. It populates no sign, signs no finding, holds no key, and makes no
authority decision. Those belong to the host, reached through the same hooks that already carry
risk tiers, approvals and receipts. The connectome is not an MCP capability: neither protocol
revision this package targets defines a topology or a declared-reachability primitive, and none
is claimed.

## The names

- A **connectome** is the graph itself: nodes and edges, each edge carrying a kind, a sign and a
  provenance.
- The **declared connectome** is built from what is declared: the catalog's tools, resources and
  prompts, the static call graph between the host's modules, and the host's boundary declarations.
  It says what *may* happen.
- The **observed connectome** is built from what ran: telemetry on the dispatch path and, when the
  host opts in, a guarded tracer. It records edge identity only — never arguments, results or
  headers. It says what *did* happen, over a stated window.
- A **drift finding** is an edge the observed connectome has and the declared connectome does not,
  or an edge both have with signs that differ. Drift is a record; what to do about it is the host's.
- **Dead authority** is an edge the declared connectome has and the observed one never showed in the
  window. It is evidence for narrowing, not a fault.
- A **coverage bound** is the measured fraction of one graph the other accounts for, stated with
  the window it was measured over. It is reported as a number, never assumed complete.

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
| `:unknown` | no policy has spoken; **the only value the package itself ever writes** |

The sign is a *slot*. The package carries it so that a rendered graph can show a policy's verdict
beside each edge; the host fills it. Nothing in the package computes one.

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

## Provenance

| provenance | which build produced the edge |
| -- | -- |
| `:declared` | the declared connectome |
| `:observed` | the observed connectome |

An edge carries exactly one provenance. Comparing the two graphs is how a drift finding is made.

## Weight

An edge may carry a weight — an observed call count, a latency summary. Weights are measurements.
They are never part of the declared connectome's canonical bytes, so the hash of a declared
connectome is a claim about wiring and nothing else.
