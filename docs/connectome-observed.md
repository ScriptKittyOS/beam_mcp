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

Every `tools/call` that reaches the host's dispatch function emits three events in the
shape `:telemetry.span/3` gives them, from one private site in `BeamMCP.Server`
(`dispatch/3`):

| event | measurements | metadata |
| -- | -- | -- |
| `[:beam_mcp, :dispatch, :start]` | `system_time`, `monotonic_time` | `server_name`, `tool`, `telemetry_span_context` |
| `[:beam_mcp, :dispatch, :stop]` | `duration`, `monotonic_time` | as start, plus `outcome: :ok \| :error` |
| `[:beam_mcp, :dispatch, :exception]` | `duration`, `monotonic_time` | as start, plus `kind`, `reason`, `stacktrace` (frames carry arities, never argument lists) |

`server_name` is the string given to `BeamMCP.Server.new/1`; `tool` is the catalog's atom.
**No argument, result or header bytes are in any measurement or metadata that the package
writes.** A call the schema refuses is not a dispatch and emits nothing. `:exception` is
`span/3`'s shape with one difference: the BEAM puts a call's argument list in the top frame
of a `function_clause` or a BIF error's stacktrace, so the frames in the event carry the
arity in that position and never the list, and a frame's location keeps file and line
only, and only as the compiler writes them — a charlist and an integer — a host can put
any term into a frame through `:erlang.error/3`'s `error_info` or hand `:erlang.raise/3`
frames of any shape, and none of it travels or breaks the rewrite; the host's own
stacktrace is re-raised untouched. The file in a frame is the path the module was
compiled from, verbatim, as in any stacktrace; a handler that ships the event off the node
ships that path. `reason` is the
exception the host's dispatch raised, whatever the host put in it (a `KeyError` can carry
the map it was asked, for one); that is the host's, and the collector never reads it. The names are identity and do enter: `server_name`, the tool's name, and
through the tracer a module's name and a registered process's name go verbatim into the
bytes a consumer signs — a secret in a name is published.

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
the samples. It is not part of any hash and not part of the canonical sidecar. The
durations are the host's dispatch function's own timing, as the counts are its own calls.

The table is public and `observe/5` is a host's to call. A row of another shape — an
identity the builders would not derive, a count below one — is refused by `snapshot/1` and
`latency/1` as `{:error, {:malformed_row, key}}`, never built into a graph.

**The table dies with its process.** A restart under the host's supervisor starts from no
rows; what a host loses is every observation since the last snapshot it kept. The declared
side is unaffected. A kill that skips the orderly stop leaves the old handler attached until
the restart replaces it; a call in that gap is answered normally, and the stale handler
fails against the missing table and is detached by telemetry, which logs one failure per
dispatching process that was in the gap. A hot reload of the collector's module keeps the
handler and the rows; a hot reload of the tracer's module purges its companion and ends a
running trace as `{:shutdown, :companion_gone}`.

## The tracer

`BeamMCP.Connectome.Tracer` sees the edges telemetry cannot: a module calling a module, a
process sending to a process. It is off until a host starts it, runs one at a time, and
refuses to start without a running collector, with a limit that is not a positive integer
— there is no unbounded mode — with the wildcard or an unloadable module in `modules:`, or
with a name in `processes:` that is not registered; a start that fails part-way clears
what it set and answers `{:error, {:init_failed, reason}}`. Calls are traced on every
process in the node, present and future.

It stops itself at `max_messages` handled trace messages of any shape, a send to a dead
process included, or at `max_duration_ms`, clearing every pattern and flag it set, and
exits `{:shutdown, {:limit, which, value}}`; `stop/0` is the third way out; each of the
three ends the tracer on the next message it handles, and what was still queued behind it
is discarded, not written; the collector dying under it is the fourth,
`{:shutdown, :collector_gone}`. **What the limits bound:**
`max_messages` counts messages as they are handled while the BEAM queues them as they
arrive, so the tracer runs at high priority and clears its patterns the moment handled plus
queued reaches the limit — generation stops there. The queue's size is the node-wide call
rate into the named modules times the tracer's scheduling latency, not `max_messages`
(measured: 64 hot callers against a limit of 1 000 peaked from some tens of thousands to
a hundred-odd thousand queued messages, run to run; with a limit too large to reach, 32 hot callers
queued some millions in a 100 ms window). The mailbox is kept off-heap, so a large queue
is not copied at every collection while it drains. The
early clear is best effort — the queue is read on the first and every 32nd message — while the hard bounds
hold on every path but the one named below: at most `max_messages` handled, the patterns
cleared at the limit and on every exit. A
companion process enforces `max_duration_ms` from outside the tracer's mailbox — clearing
the patterns at the deadline and raising a flag the tracer reads on every message it
handles, so at most one row lands after it is raised — and
clears on the tracer's exit for any reason, a kill included, so no pattern is left set with
no tracer behind it: a leftover pattern would cost every call to that module a breakpoint
and would feed a host's own later call tracer with arguments. The tracer watches the
companion back and exits `{:shutdown, :companion_gone}` if it dies. One window is open:
the companion killed and then the tracer killed before it handles that death leaves the
patterns set until the next `start/1` or `stop/0`, either of which clears what the
tracer's running term names. That term, `{BeamMCP.Connectome.Tracer, :running}`, is a
public persistent term and is trusted only in its own shape — a three-tuple whose second
element is a list of module atoms; a term of another shape put there by someone else
names nothing, is erased by the next `start/1` or `stop/0` or by the tracer's own exit,
and makes neither raise; a term of the right shape put there by someone else names what
it names, and the next `start/1` or `stop/0` clears those modules' patterns, a host's own
included. A running tracer's `stop/0` reads the tracer's own claim — flag, modules, the
named processes — from the tracer's process dictionary, which nothing outside it can
write; its companion holds the same claim from the start, and reads a dictionary only to
learn what a tracer running at its death claims. A claim of another shape — a process
that took the tracer's name and put one there — is no claim: `stop/0` is `:ok` and clears
nothing it names. So a forged term neither delays a stop nor passes for a newer tracer's
claim. A
`start/1` waits a bounded second for a previous companion still clearing after a kill;
`stop/0` waits a bounded five seconds for the tracer to leave and is `:ok` either way. A
companion that outlives a kill clears only the modules no tracer running at that moment
claims. A `:send` trace message
carries the sent term into the tracer's mailbox until it is handled, where anything that
can read that process's queue can see it; nothing of it is written. Nothing is cleared
that the tracer, or a stale running term, did not name — its patterns and the send flag
on the processes it named, resolved once at start and cleared only where this tracer's is
the flag on them: a name reused during the run belongs to another process, and a process
a host re-traced under its own tracer keeps that; never every process's flags. Patterns are global in the BEAM;
clearing a module's patterns clears any someone else set on it. The collector dying under the tracer is met as its DOWN
or as the first write into the table that is gone, whichever is first in the queue, and is
`{:shutdown, :collector_gone}` either way. It never calls `:dbg`.

**The threat model, which is the boundary of every claim in this section.** In scope:
accident and failure on a node running only code the host put there — crashes, kills,
restarts and the host's supervisor, a registered name reused by an unrelated process, a
host tracing its own processes, hot reload, starvation under load, the public API called
wrongly or in the wrong order, and a stale running term left by a previous crash of this
module. Out of scope: an adversary executing code inside the same BEAM node — a process
that registers itself under the tracer's name, a forged persistent term, a crafted process
dictionary. Such an adversary can already read the collector's ETS table directly, call
the host's dispatch function, replace a module with `:code.load_binary/3`, or trace every
process itself. The tracer is not a security boundary against it, and nothing this package
can do makes it one; a reader who takes it for one is in more danger than one who knows it
is not. The shape guards on the running term and on the claim are robustness, not
defence: they keep `stop/0` and `start/1` total against a term of the wrong shape, which
the stale-term-after-crash case — in scope — needs.

What it writes, through the same collector: a call into a traced module as a
module-level `:invoke` edge from the caller's module to the callee's, with the `:arity`
flag so no argument ever reaches it; a send from a traced registered process to a
registered process as a `:message` edge by name, the message term never read, a send to an
unregistered process dropped rather than written under a pid.

Three bounds, measured: a call in tail position has no frame of its own, so the BEAM names
the caller's caller; names are resolved when a trace message is handled, so a process that
exited or unregistered in between is dropped; and OTP's own registered processes — the
code server, a logger handler, telemetry's table owner — are names like any other, so a
traced process's sends to them are edges too. The tracer never traces its own writes: the
BEAM discards an event whose tracer is the process that generated it.

## What never enters

A payload marker sent inside a nested argument map, as a resource URI argument, in an
error the dispatch returns and in an exception it raises is asserted absent from every
row, from the snapshot's canonical bytes, from the sidecar and from the latency summary,
by the tests that pin this page.
