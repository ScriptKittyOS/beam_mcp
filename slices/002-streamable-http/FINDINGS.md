# Slice 002 — findings

Three review rounds, eight lanes. This is the record of what was wrong and who found it, kept
because the pattern across the rounds is more useful than any single finding.

## The pattern, stated first

**Each round's fixes bred the next round's blockers.**

| round | blockers | how many were caused by the previous round's fixes |
|---|---|---|
| 1 | 7 | — |
| 2 | 2 blocking + 5 filed | 2 of 2 — both were shapes fixed once in the same commit that reintroduced them |
| 3 | 4 blocking across 3 lanes | 2 of the 3 highest — the rescue rework and the Base64 scoping |

That base rate is why round 3 and round 4 exist. It is not caution; it is a measured probability
that a fix of this size carries a regression, and it was measured on this slice.

## Attribution, where it belongs

**The rescue regression is the coordinator's, recorded as such at the coordinator's instruction.**

The instruction was to wrap the whole of `call/2` rather than add five guards, and that shape was
right: eight inputs were producing a bare bodyless 500 and one produced no response at all,
because the refusal path itself sat outside every rescue. What neither of us considered was the
exceptions already passing through that path **carrying meaning**. `Bandit.HTTPError` has a
`plug_status`, so the wrap turned `408` into `500`, `400` into `500`, and every stalled connection
into an unauthenticated 5xx with an error-level stacktrace in the host's log.

The class fix was right in shape and wrong in blast radius, and the difference between those two
is exactly what a lane exists to find. `Plug.Exception.status/1` — Plug's own protocol, so it
holds for adapters other than Bandit and needs no reference to a module that may not be loaded —
is a better answer than either of us had going in.

The lane proved it a regression rather than arguing it: the same probe against `a5cfb67` returned
408/400/400 and against `HEAD` returned 500/500/500.

## My own instrument failing — the two self-corrections

These carry the same weight as the lanes' findings. They are the hardest class to catch, because
the thing that is broken is the thing doing the checking, and nobody else can catch them for you:
a lane reads the code, not the reasoning that produced the evidence about the code.

**1. "One mutant per header read" was one mutant per header NAME.** `compare_versions/3` performs
two value comparisons on `MCP-Protocol-Version` and I pinned one. A first-value-only mutant on the
second **survived the entire suite** — and that branch is the only version check that runs on a
body carrying no `_meta`, which is every request that does not declare its era in the body. The
round-2 finding was "you counted the reads you had in mind rather than the reads the code makes",
and the evidence I produced to close it made the same error one level down.

**2. The derivation grep was misreported.** The record and the code comment both said
`grep 'get_req_header'` returns the helper and the `mcp-param-` sweep. It does not: the sweep
reads `conn.req_headers` and never calls `get_req_header`, and the grep also matches the comment
describing itself. The completeness argument rested on quoted output that did not say what it was
quoted as saying — which is the same defect as a gate reporting a verdict without running its
probe, in the place where the verdict was mine.

## The sharpest finding, as a rule rather than an incident

`Mcp-Param-{Name}` derived its population **from the request**.

That is not a missing derivation. It is a derivation from the wrong side of the trust boundary,
and from inside it, it looks identical to the correct one — no hand-written list, a new header
inherits the behaviour. It made the specification's *"client omits the header but the value is in
the body → server MUST reject"* unenforceable by construction: a server whose set comes from the
caller's headers cannot see an omission.

Now in `CONVENTIONS.md` as **"Deriving from attacker-controlled input is not deriving a
population"**, because "derive it" has been the answer often enough here that the next reader will
apply it without asking *from what*.

## Round-by-round

### Round 1 — seven blocking

The package did not compile without `plug` (`optional: true` governs resolution, not compilation);
`inspect(reason)` leaked a planted bearer token and a `postgres://` URL into a 403 body served to
an unauthenticated caller; a non-map `_meta` crashed outside the rescue; `Mcp-Method`/`Mcp-Name`
were neither required nor validated — the spec's own named vulnerability; an unimplemented method
answered `200`; five error paths poisoned keep-alive through a `with/else` binding loss, visible
only at ≥16 KB; `throw`/`exit` escaped `rescue`.

My own probe failures in that round: a dispatch-crash probe that silently did not apply and was
reported as a `200`; server options passed by a hardcoded `Keyword.take` that silently dropped two
new ones; and an acceptance criterion written impossibly.

### Round 2 — two blocking, both reintroductions

Only the first value of `Mcp-Method`, `Mcp-Name` and `MCP-Protocol-Version` was validated — the
smuggling shape fixed for `Origin` in the same commit that wrote three new single-value reads. And
the refusal path sat outside every rescue.

The round-1 multi-`Origin` fix had **no test at all**: `Enum.all?` → `Enum.any?` survived 82/82.
Right, unpinned, and nothing would have caught its removal.

### Round 3 — four blocking, two of them caused by round 2

The rescue regression above; Base64 decoding applied to every header, which let
`Mcp-Method: =?base64?…?=` satisfy this server while a gateway saw an opaque token; the
`Mcp-Param` population derived from the request; `initialize` answering `200` with
`protocolVersion: "2025-11-25"` while the README said it was not implemented; and
`Code.ensure_loaded?` in `init/1` rejecting a valid catalog that lives in the host's own project.

`tools/probe_optional_deps.sh` passed throughout — it proves the package **compiles**, not that a
host can **start**.

## Evidence

`logs/mutation.md` — 23 mutants across three rounds, each asserted applied before scoring, with
one recorded equivalent survivor and three compiler-kill completions. `logs/round{1,2,3}.*.md` —
the lanes' own reports. `logs/gate-round{2,3}.txt` — the gate at each boundary.
