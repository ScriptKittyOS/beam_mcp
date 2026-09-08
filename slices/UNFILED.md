<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# UNFILED — findings with no Linear issue

**Why this file exists.** The Linear workspace is at its free issue limit:

    You've exceeded the free issue limit for this workspace.

Findings that cannot be filed are recorded as comments on the nearest open issue, and a comment
thread is not a place a finding can be found. This is the single running list, so nothing lives
only in a thread. Owner decision, 2026-09-07.

**The rule for this file.** Each entry names the round and the lane that found it, states the
derivation, and says whether it is a live defect or cleanup. An entry leaves this file when it
gets an issue or when it ships — and it leaves by being deleted with the commit that discharges
it, not by being marked done here.

---

## Being fixed in slice 003 (release 0.3.1) — no issue, tracked only here

These three were found by the 002 review lanes and re-ranked into slice 003 by owner decision
2026-09-07. They have no Linear issue. **If slice 003 does not ship them, they revert to
unfiled** and this note is what remains of them.

### An `x-mcp-header` on a non-primitive property makes the tool permanently uncallable

**Live defect. Shipped in 0.3.0. Round 4, lane s1, Finding 5.**

`value_matches?/2`'s catch-all returns `false` for maps, lists and floats. `x-mcp-header` "MUST
only be applied to parameters with primitive types (integer, string, boolean)", so refusing is
right — but an annotated non-primitive can then never match, and both escape routes close: the
client cannot omit the header (the body carries a value to mirror) and cannot supply one (it can
never match). **`number` is caught by this too**, and the specification permits `integer`, so a
host annotating a float property ships a tool nobody can call. The invalid definition is accepted
silently at `init/1`, advertised in `tools/list`, and then refused at every call with a `400` that
names the caller's header as the problem.

Derivation and exploit: `slices/002-streamable-http/logs/round4.s1.md`.

### Colliding `x-mcp-header` names collapse silently — SCR-275

Filed, unlike the rest of this section. Listed here only because slice 003 fixes it on the same
enforcement surface as the entry above.

### A host *data* fault loses the request id

**Live defect. Shipped in 0.3.0. Round 7, lane v1, Finding 4.**

`annotations(spec.input_schema)` is read in the `with` body, outside `host_call/1`. So a catalog
returning a spec-shaped map that is not a `ToolSpec` raises there and escapes to `call/2`'s
rescue, which answers `"id":null` — while a catalog *raising* two lines earlier is caught by
`host_call/1` and answered with the request's id. Measured:

    host tool raises (dispatch/3)                    500  -32603  id echoed
    host tool_catalog RAISES (header validation)     500  -32603  id echoed
    host tool_catalog returns a malformed spec       500  -32603  id null
    host authorize/1 raises                          500  -32603  id null

The last row is necessary — `authorize/1` runs before the body is read. The third is not.
Archive: `slices/002-streamable-http/logs/probe-fault-ids.txt`. Moving the read inside
`host_call/1` is mutant **M13** in `logs/mutation-round7.txt`, which is why it needs its own red.

### Pre-read refusals answer without `connection: close`

**Live defect. Shipped in 0.3.0. Round 6, lane s3, Finding 6.**

Every refusal that fires before `read_body/2` answers on a conn with an unread body and no
`connection: close`; Bandit then drops the connection, so a pipelined second request is never
answered. Measured:

    ok authorize (baseline, 200)              second-request-answered=True
    authorize raises -> 500                   second-request-answered=False
    catalog raises (after read_body) -> 500   second-request-answered=True

Applies equally to the Origin `403`, the authorize `403` and the `405`. It fails **closed** — no
misframing, no smuggling — which is why it ranks below the other three.
`read_body_bounded/1`'s `413` already calls `close_after/1`.

---

## Waiting for board capacity — cleanup, explicitly out of slice 003

### `fault_response/4`'s re-raise branch is unpinned

**Cleanup, not a defect. Round 6 lane s3 (S3-2) and round 7 lane v1.**

Measured: the mutant that never re-raises survives at `137 tests, 0 failures`. Detecting it needs
an exception with a non-500 `:plug_status` raised by code that is *not* the host's — which after
round 5's fix means the adapter's read path alone (`Bandit.HTTPError` at 400,
`Plug.TimeoutError` at 408). `Plug.Test`'s `read_body/2` is a `:binary.part` of an in-memory
binary and produces neither. **Closing it needs a Bandit-backed test.** No wrong behaviour ships;
the branch is simply unguarded.

The answer branch *is* pinned, by mutant M2 in `logs/mutation-round7.txt`.

### `BeamMCP.ToolCatalog.fetch/2`'s `@spec` is not honest

**Cleanup. Round 4, lane s1, Finding 6.**

`@spec fetch(module(), String.t() | atom()) :: {:ok, t} | :error`, but three host-authored catalog
shapes raise instead: a binary `spec.name` (`ArgumentError`), `all/0` returning a non-list
(`Protocol.UndefinedError`), and an unloaded module (`UndefinedFunctionError`). All are host bugs
rather than attacker inputs, and `init/1` guards the third for the transport's own use. But the
function became public API in 0.3.0 and is documented as the one lookup every caller should use,
and a public function that says `:error` and raises will be called without a rescue. Either widen
the `@spec` and say so in the `@doc`, or make the clauses total.

### No conformance test derives its assertions from the specification's required-field list

**Cleanup, and it outlives the issue it came from. Filed under SCR-261, which is now Done.**

SCR-261 is closed because `ttlMs` and `cacheScope` ship. Its deeper point does not close with it:
nothing derives the modern era's required result fields from the specification, so the next
required field is missed exactly the way that one was — identified in a PLAN, two of three
implemented, the third unnoticed until a lane read the spec again.

### `readme_claims_test.exs` does not deliver what `CONVENTIONS.md` asks

**Owner decision, not a fix. Round 7, lane v1, Finding 7.**

`CONVENTIONS.md` says "Every behavioural claim in it is pinned by a test that runs." The file pins
every claim *listed in it*, and nothing enumerates the README's claims to prove each has a test.
Three rounds running, that gap caught the commit citing the rule — each time a new behavioural
claim shipped unpinned in the same commit that pinned others.

An earlier version of the file's moduledoc said the rule had been narrowed to match. It had not:
`git log -S` finds the broad wording added once and never changed. That misattribution is
corrected; the gap is not. Closing it means either a mechanism that derives the README's claim
set, or an owner decision to narrow the rule.
