<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# The connectome — the observed side

The declared connectome is built from the tree. The observed one is built from what ran:
the dispatch path emits, a collector the host starts turns emissions into edges, and a
snapshot is a graph with `provenance: :observed` and every sign `:unknown`. What follows
is the contract a consumer attaches to and the bounds of what it sees.

## The events

Every `tools/call` that reaches the host's dispatch function is wrapped in one
`:telemetry.span/3`, at one private site in `BeamMCP.Server` (`dispatch/3`):

| event | measurements | metadata |
| -- | -- | -- |
| `[:beam_mcp, :dispatch, :start]` | `system_time`, `monotonic_time` | `server_name`, `tool`, `telemetry_span_context` |
| `[:beam_mcp, :dispatch, :stop]` | `duration`, `monotonic_time` | as start, plus `outcome: :ok \| :error` |
| `[:beam_mcp, :dispatch, :exception]` | `duration`, `monotonic_time` | as start, plus `kind`, `reason`, `stacktrace` |

`server_name` is the string given to `BeamMCP.Server.new/1`; `tool` is the catalog's atom.
**No argument, result or header bytes are in any measurement or metadata.** A call the
schema refuses is not a dispatch and emits nothing. `:exception` is `span/3`'s own shape:
its `reason` is the exception the host's dispatch raised, whatever the host put in it, as
for every library that uses `span/3`. The collector never reads it.

## The collector

`BeamMCP.Connectome.Observed` is a process the host adds to its own supervision tree and
names; the package starts nothing. Running, it owns one ETS set and one handler on `:stop`
and `:exception` — a call that returned and a call that raised are both an attempt, and the
edge is the attempt. Each attempt is one row keyed by the edge's identity (the server node,
the tool node, `:invoke`), holding a count and a latency summary; a repeated call is the
same row with the count incremented, so the table is bounded by the number of distinct
edges and never by the number of calls. Writes happen in the caller's process, into a
public table with write concurrency; the owner holds the table's lifetime and is never on
the hot path. Per-call cost is a number in the release notes, not a claim here.

`snapshot/1` is the graph: one node per server and tool seen, one edge per row with the
count as its weight, every sign `:unknown`, built through the same constructors as the
declared side, on the same ids — the two graphs join on ids and on edge keys. Observed
nodes carry no labels: the collector saw a call, not a catalog entry, so a declared tool
node and its observed counterpart differ in `labels` while sharing an id. When no collector runs under the
name it is a **named refusal**, `{:error, :not_started}`, and not an empty graph: an empty
observed connectome says "nothing ran", which is a different claim from "nothing was
watching", and a diff that took the first for the second would report every declared edge
as dead authority. A running collector that has seen no calls is an empty graph.

`latency/1` is a summary per edge — count, mean and maximum in microseconds — and never
the samples. It is not part of any hash and not part of the canonical sidecar.

**The table dies with its process.** A restart under the host's supervisor starts from no
rows; what a host loses is every observation since the last snapshot it kept. The declared
side is unaffected. A kill that skips the orderly stop leaves the old handler attached until
the restart replaces it; a call in that gap is answered normally, and the stale handler
fails once against the missing table and is detached by telemetry, logged once.

## The tracer

`BeamMCP.Connectome.Tracer` sees the edges telemetry cannot: a module calling a module, a
process sending to a process. It is off until a host starts it, runs one at a time, and
refuses to start without a running collector or with a limit that is not a positive
integer — there is no unbounded mode. It stops itself at `max_messages` trace messages or
`max_duration_ms`, clearing every pattern and flag it set, and exits
`{:shutdown, {:limit, which, value}}`; `stop/0` is the third way out; the collector dying
under it is the fourth, `{:shutdown, :collector_gone}`, which it watches for rather than
failing on the next traced call. It never calls `:dbg`.

What it writes, through the same collector: a call into a traced module as a
module-level `:invoke` edge from the caller's module to the callee's, with the `:arity`
flag so no argument ever reaches it; a send from a traced registered process to a
registered process as a `:message` edge by name, the message term never read, a send to an
unregistered process dropped rather than written under a pid.

Two bounds, measured: a call in tail position has no frame of its own, so the BEAM names
the caller's caller; and names are resolved when a trace message is handled, so a process
that exited or unregistered in between is dropped.

## What never enters

A payload marker sent inside a nested argument map, as a resource URI argument, in an
error the dispatch returns and in an exception it raises is asserted absent from every
row, from the snapshot's canonical bytes, from the sidecar and from the latency summary,
by the tests that pin this page.
