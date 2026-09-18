<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# The connectome — the observed side

The declared connectome is built from the tree. The observed one is built from what ran:
the dispatch path emits, a collector the host starts turns emissions into edges, and a
snapshot is a graph with `provenance: :observed` and every sign `:unset`. What follows
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
frames of any shape, and none of it travels or breaks the rewrite — a frame whose arity
position is neither a list nor an integer is dropped from the event, as a fun frame is;
the host's own stacktrace is re-raised untouched. The rewrite has a name,
`BeamMCP.Stacktrace.arities/1`, and one implementation: the HTTP transport's fault log
writes the same frames, so a caller's arguments reach neither an event nor a host's log. The file in a frame is the path the module was
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
count as its weight, every sign `:unset`, built through the same constructors as the
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
with a name in `processes:` that is not registered; a start that fails part-way leaves
nothing set and answers `{:error, {:init_failed, reason}}` — a name in `processes:`
registered to a port rather than a process, or whose holder exited between the check and
the start, is the cause that remains.

**One trace session, the tracer's own.** Everything the tracer sets it sets inside one
OTP trace session (`:trace.session_create/3`, OTP 27 — the reason this package's floor is
27) whose tracer is the tracer process: the call patterns on the named modules, the call
flag on every process in the node, present and future, and the send flag on the named
processes. Sessions are isolated from each other and from the legacy `:erlang.trace/3`
session a host may be using. So a process a host already traces is traced by this
session as well and its calls are edges (measured: both tracers received the call — under
the legacy tracer the BEAM skipped such a process silently, one tracer per process, and
its calls were no edges); a host's own pattern on a module the tracer names is neither
fed by the tracer's pattern nor touched by its clear (measured: the host's call tracer saw
only what its own pattern generated, and its pattern read `local` after the tracer's
session was gone); and nothing here reads or clears a flag or a pattern that is not the
session's — a host's flags on any process, its patterns on any module, its own sessions,
all survive the tracer's start, stop, deadline, limit and kill alike. The legacy view,
`:erlang.trace_info/2`, does not see a session's settings at all: a host reading it will
find none of the tracer's, which is the isolation working, not a tracer that set nothing;
the tests that pin this page read `:trace.session_info/1`.

It stops itself at `max_messages` handled trace messages of any shape, a send to a dead
process included, or at `max_duration_ms`, destroying its session — every pattern and
flag it set, in one call — and exits `{:shutdown, {:limit, which, value}}`; `stop/0` is
the third way out; each of the three ends the tracer on the next message it handles, and
what was still queued behind it is discarded, not written; the collector dying under it
is the fourth, `{:shutdown, :collector_gone}`. **What the limits bound:** `max_messages`
counts messages as they are handled while the BEAM queues them as they arrive, so the
tracer runs at high priority and destroys its session the moment handled plus queued
reaches the limit — generation stops there. The queue's size is the node-wide call rate
into the named modules times the tracer's scheduling latency, not `max_messages`
(measured: 64 hot callers against a limit of 1 000 peaked from some tens of thousands to
a hundred-odd thousand queued messages, run to run; with a limit too large to reach, 32
hot callers queued some millions in a 100 ms window). The mailbox is kept off-heap, so a
large queue is not copied at every collection while it drains. A `:send` trace message
carries the sent term: a traced process's sends are copied into the tracer's mailbox at
their own size until they are handled and dropped unread (measured: one traced send of a
million-element list put 16 MB on the tracer), so that bound is the traced processes' own
message sizes; nothing of a term is written, and anything that can read the tracer's
queue can see one while it waits. The early clear is best effort — the queue is read on
the first and every 32nd message — while the hard bounds hold on every path: at most
`max_messages` handled, the session destroyed at the limit and on every exit. A companion
process enforces `max_duration_ms` from outside the tracer's mailbox — raising a flag at
the deadline and then destroying the session; the tracer reads the flag before every
write, so nothing lands after it is raised. The tracer watches the companion back and
exits `{:shutdown, :companion_gone}` if it dies.

**Nothing left behind, on every path.** The session's handle is held by the tracer and by
its companion and by nothing else the tracer writes — never in a persistent term, which
would keep a dead tracer's session, and its breakpoints, alive until erased (measured); a
copy anywhere is a holder too, and `:sys.get_state/1` on the tracer makes one on the
caller's heap that holds the session up until that process next collects (measured: 50 ms
after both holders had died, the session was still listed). `stop/0`, the
limit, the deadline and `terminate/2` each destroy the session by name; and a session
whose every handle is gone is destroyed by the BEAM itself (measured: the last holder
killed, the pattern was gone within 20 ms). The companion monitors the tracer and exits
on its exit — a kill included, which skips `terminate/2` — and that exit is the clear: the
last holder gone, the session goes with it. The window the legacy tracer left open, the
companion killed and then the tracer killed before it handles that death, closes the same
way: both holders gone, the session with them, whatever modules it named; there is no
running term to clear, no stale term for a next `start/1` to read, and no wait for a
previous companion. A session whose tracer has died but whose handle is still held keeps
its patterns set — the BEAM drops a dead tracer's process flags, not its patterns — at a
cost per call into those modules (measured: 200 000 calls, from the baseline's order to
2.4 times it, run to run): a companion suspended from outside is such a holder, and
`terminate/2`'s own destroy is what ends the session on an orderly exit while it is; a
start that fails part-way destroys its session before the reason leaves `init/1`, since
the error term carries the raise's arguments, the handle among them; a
companion that outlives its tracer that way destroys its own session and no other, since
a handle reaches one session and a later tracer's is another. A running tracer's `stop/0`
reads the tracer's own claim — the flag and the session handle — from the tracer's
process dictionary, which nothing outside it can write, raises the flag and destroys the
session before asking the tracer to stop, and waits a bounded five seconds for it to
leave, `:ok` either way; a claim of another shape — a process that took the tracer's name
and put one there — is no claim, and a term in it that is no handle destroys nothing.
`stop/0` with no tracer running is `:ok` and touches no session. The collector dying
under the tracer is met as its DOWN or as the first write into the table that is gone,
whichever is first in the queue, and is `{:shutdown, :collector_gone}` either way. The
tracer traps exits, so an exit signal from a process that is not its parent is a message
it ignores, not a stop: tracing goes on to its limits, and `stop/0` is the way to end it
from outside. It never calls `:dbg`.

**The threat model, which is the boundary of every claim in this section.** In scope:
accident and failure on a node running only code the host put there — crashes, kills,
restarts and the host's supervisor, a registered name reused by an unrelated process, a
host tracing its own processes under the legacy tracer or under a session of its own, hot
reload, starvation under load, and the public API called wrongly or in the wrong order.
Out of scope: an adversary executing code inside the same BEAM node — a process that
registers itself under the tracer's name, a crafted process dictionary, a handle taken
from the tracer's dictionary and destroyed. Such an adversary can already read the
collector's ETS table directly, call the host's dispatch function, replace a module with
`:code.load_binary/3`, or trace every process itself. The tracer is not a security
boundary against it, and nothing this package can do makes it one; a reader who takes it
for one is in more danger than one who knows it is not. The shape guard on the claim is
robustness, not defence: it keeps `stop/0` total against a claim of the wrong shape. The
same line, drawn for the whole package and for the wire, is `docs/threat-model.md`.

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
