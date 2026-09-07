<!--
Written by reviewer lane r2 itself, not transcribed by another party. These are the bytes r2
returned to the coding agent at the end of round 1, unabridged, from the four header lines
through the VERDICT line.

Omitted, and named here so the omission is not silent: the two-line conversational preamble
that preceded the report in r2's reply ("I have everything I need. Writing the report." and a
horizontal rule). Nothing inside the report is abridged, reordered or reworded.

No SPDX header: this file sits beside the other logs/ archives, which carry none, and
tools/gate.sh derives its REUSE population from '*.ex' '*.exs' '*.sh' '*.yml' only. If .md is
ever added to that population this file and the two spec archives all need a decision.
-->

From: beam_mcp · Reviewer lane r2
To: beam_mcp · Coding Agent
Re: slice 001b-ping-guard, round 1, security, contract and evidence integrity
Type: Report

**Tree read:** `a42f1b1e82599b203df0afcaaa8639203fd663d7`

```
$ cd /home/aylac/Projects/beam_mcp-wt/001b-review && git write-tree
a42f1b1e82599b203df0afcaaa8639203fd663d7
```
Written to `/home/aylac/Projects/beam_mcp-wt/001b-review/logs-r2.tree`. No file under review was modified; all probes ran either in this throwaway checkout or in a copy at `<scratch>/r2/before/` built with `tar` + `git show base/main:…` (no `.git`, own `_build`).

---

## Answer to the security question first, because it is clean

**The change does not widen the attack surface.** `tools/call` was *already* reachable through `_meta` naming `2025-11-25` at `base/main`, because the old `cond` at `lib/beam_mcp/server.ex:124` (base) tested `version not in @supported_versions`, and `2025-11-25` **is** in `@supported_versions` (`server.ex:42`). Only `ping` took the refusal branch; everything else fell to `true ->` and was served. So the new `@legacy_version` branch at `server.ex:142-145` adds exactly one newly-reachable method — `ping`, which returns `result(id, %{})` at `server.ex:156-158` and touches no state, no catalog and no dispatch.

Both branches converge on the same call: `handle_message(state, bare)` (`server.ex:138` modern, `server.ex:145` legacy) → the `tools/call` clause at `server.ex:165-192` → `validate_and_dispatch/3` at `server.ex:282-292` → `Schema.validate/2` before `state.dispatch.(…)`. Validation is not merely "still applied" — it is the *same* code path with no version-dependent branch anywhere between the era switch and the dispatch call. Demonstrated, identical rejections on both branches and at both refs:

```
$ mix run <scratch>/r2/probe_r2.exs      # in the review checkout, 0.1.2
tools/call legacy _meta, INVALID args (missing required)
  -> {"id":4,...,"result":{"content":[{"text":"strict_echo: invalid arguments: missing required property: text",...}],"isError":true,...}}
tools/call modern _meta, INVALID args (missing required)
  -> {"id":4,...,"result":{"_meta":{...},"content":[{"text":"strict_echo: invalid arguments: missing required property: text",...}],"isError":true,"resultType":"complete",...}}
tools/call legacy _meta, INVALID args (additionalProperties)
  -> ... "invalid arguments: unknown property: x" ... "isError":true
tools/call modern _meta, INVALID args (additionalProperties)
  -> ... "invalid arguments: unknown property: x" ... "isError":true
tools/call UNSUPPORTED version -- does dispatch run?
  -> {"error":{"code":-32022,...}}          # dispatch not reached
```
The same script against the `base/main` copy returns the byte-identical bodies for every `tools/call` case (only the added `resultType`/`_meta` decoration differs). Dispatch is unreachable on the `_other` branch (`server.ex:147-148`) — the `-32022` is returned *before* any recursion.

Enumeration of the legacy branch, measured, `mix run <scratch>/r2/probe_r2.exs` section D:

| method | through legacy `_meta` | reached via |
|---|---|---|
| `server/discover` | result | `server.ex:92` (clause precedes `_meta`) |
| `initialize` | result, sets `initialized?` | `server.ex:102` (clause precedes `_meta`) |
| `notifications/initialized` | `nil` | `server.ex:152` |
| `ping` | `{"result":{}}` | `server.ex:156` — **the only new reachability** |
| `tools/list` | result | `server.ex:160` |
| `tools/call` | dispatch, schema-validated | `server.ex:165` — reachable before, unchanged |
| `shutdown` | sets `shutdown?` | `server.ex:194` — reachable before |
| `exit` | `nil`, sets `shutdown?` | `server.ex:198` — reachable before |
| unknown | `-32601` | `server.ex:202` |

No recursion hazard: `bare = Map.drop(message, ["_meta"])` at `server.ex:129` removes the only key that can re-match the clause head, so the recursive call at `:138`/`:145` cannot re-enter. A nested `_meta` under `params` does not re-enter either (measured, section E).

**Untrusted input: every value is handled, nothing crashes, no atom growth.** `mix run <scratch>/r2/probe_r2.exs`, sections A/B/F/G:

```
version = 42 / null / true / ["2025-11-25"] / {"v":"…"} / "" / " 2025-11-25"
  -> all: {"error":{"code":-32022,"data":{"requested":<echoed as-is>,"supported":[...]},...}}
_meta = "2025-11-25" | [] | 7 | null | {}   (method ping)
  -> all: {"id":1,"jsonrpc":"2.0","result":{}}   (clause head does not match; falls through)
atom_count before=24154 after=24154 delta=0   # 20 000 distinct unknown version strings
atom_count before=24154 after=24154 delta=0   # 20 000 distinct undeclared tools/call argument keys
```
No `FunctionClauseError`, no raise, no throw, on any of the 30 shapes probed (the probe wraps every call in `rescue`/`catch` and would have printed `RAISED`/`THREW`). `case version do` at `server.ex:131` has a total `_other` fallback, and `String.to_atom/1` at `server.ex:318` is fed only from schema-declared property keys, never from the wire.

---

## Findings

### 1. `logs/probe-after.txt` is not an archive of the tree under review — non-blocking

`slices/001b-ping-guard/logs/probe-after.txt:3` and `:16`; `mix.exs:7`.

**Observed** — the file offered as the *after* measurement reports `beam_mcp version: 0.1.1`, and the modern `tools/list` result it archives embeds `"io.modelcontextprotocol/serverInfo":{"name":"beam_mcp","version":"0.1.1"}`. The reviewed index has `mix.exs:7` `@version "0.1.2"`, and `@server_version` at `server.ex:49` is compiled from exactly that value.

**Expected** — an *after* archive shows the state being shipped. Re-running the same probe on the index:

```
$ mix run <scratch>/r2/probe_ping_repro.exs     # review checkout
beam_mcp version: 0.1.2
ping + _meta 2026-07-28       -> {"error":{"code":-32601,...}}
ping + _meta 2025-11-25       -> {"id":1,"jsonrpc":"2.0","result":{}}
ping + _meta, no version key  -> {"id":1,"jsonrpc":"2.0","result":{}}
ping bare                     -> {"id":1,"jsonrpc":"2.0","result":{}}
tools/list + _meta 2025-11-25 -> {"id":2,...,"result":{"tools":[...]}}
tools/list + _meta 2026-07-28 -> {...,"serverInfo":{"name":"beam_mcp","version":"0.1.2"},...}
```
Every protocol-relevant byte matches the archive; the two version strings do not. So the archive was captured after the `lib/` edit and **before** the `mix.exs` bump, and it is the only record in the slice of what the modern envelope emits — which is precisely the field the bump changes. `FINDINGS.md:9-11` claims each log "was written by the command that produced it", which is true of the bytes; `FINDINGS.md:76` then lists it under **Green** with no note that the tree it measured is not the tree being committed. Re-take it, or annotate line 76 with the version it was taken at.

### 2. `README.md:96` states an envelope invariant the server does not keep — non-blocking

`README.md:96` (new line) vs `lib/beam_mcp/server.ex:89-99` and `:344-345`.

**Observed** — the new table row reads `| result envelope | resultType and _meta serverInfo | neither; … |`, and `README.md:98` says `server/discover` is served "at both eras". The `server/discover` clause at `server.ex:92` precedes the `_meta` clause, so its result is never passed through `modernise/2`:

```
$ mix run <scratch>/r2/probe_envelope.exs
modern _meta + server/discover
  -> {"id":1,"jsonrpc":"2.0","result":{"capabilities":{...},"protocolVersions":[...],"serverInfo":{...}}}
modern _meta + shutdown
  -> {"id":1,...,"result":{"_meta":{"io.modelcontextprotocol/serverInfo":{...}},"resultType":"complete"}}
```
**Expected** — either the row carries the `server/discover` exception, or the gap joins the `ttlMs`/`cacheScope` entry in `FINDINGS.md:118-123` ("Recorded, not fixed"). As it stands the package's own comment at `server.ex:344` ("2026-07-28 requires `resultType` on every result") and its README assert an invariant a one-command probe falsifies on a **mandatory** method. Pre-existing in `lib/`; the *claim* is new in this diff, which is what makes it in scope.

### 3. A wire-visible field removal ships under `### Fixed` with no `### Changed` and no breaking marker — non-blocking, but decide it deliberately

`CHANGELOG.md:12-40`, `mix.exs:7`.

**Observed** — `grep -nic 'breaking' CHANGELOG.md` → `1`, and that one occurrence is in the `0.1.0` section (line 156, "without a breaking change"). `grep -n '^### ' CHANGELOG.md` shows the `0.1.2` section has `### Fixed` and `### Note on 0.1.1` only.

**Both sides, as asked.**

*For `0.1.2`.* Semver §4 puts `0.y.z` outside the compatibility contract entirely. The behaviour removed was never advertised: `server/discover` returns `["2026-07-28","2025-11-25"]` (`server.ex:95`), the `-32022` payload lists `2025-11-25` as supported (`server.ex:339`), and the spec's retry advice generates the very message that was being refused — so a consumer depending on `ping + _meta 2025-11-25` → `-32601` was depending on the server contradicting its own advertisement. `0.1.1` was never published, so the only released baseline is `0.1.0` and this is the first patch over it.

*Against.* For a published Hex package the JSON on the wire **is** the API, and this removes two fields from results for an input that previously produced them — not only for `ping`. Measured, same request, two refs:

```
base/main : tools/list + _meta 2025-11-25 -> {"result":{"_meta":{"io.modelcontextprotocol/serverInfo":{...}},"resultType":"complete","tools":[...]}}
index     : tools/list + _meta 2025-11-25 -> {"result":{"tools":[...]}}
```
A `0.1.0` client that sends legacy `_meta` and reads `result.resultType` gets `nil` after upgrading a *patch*. In the Elixir/Hex convention where `0.MINOR` carries the breaking axis, `0.2.0` is the honest signal. At minimum the entry needs a `### Changed` sub-head or one sentence saying two fields are removed from legacy-declared results — the after-block at `CHANGELOG.md:29-32` shows it, but a reader scanning `Fixed` will not read it as a removal. I do not insist on `0.2.0`; I do insist the removal is labelled.

### 4. `README.md:94` — "session … yes" is not enforced anywhere — note

`grep -rn 'initialized?' lib/` returns four hits: the type at `server.ex:60`, the initialiser at `:71`, and two **writes** at `:113` and `:153`. There is no read. A bare `tools/call` with no `initialize` dispatches:

```
tools/call bare, VALID args -> {"id":3,...,"result":{...,"dispatched":"strict_echo"},"isError":false}
```
The `yes` in that cell is pre-existing; this diff amends the cell (`, unless declared through _meta`), which is a good moment to say the session is tracked and not enforced.

### 5. `server.ex:119` — the new comment overstates the clause's reach — note

The comment says "A request carrying per-request `_meta` is served statelessly … whatever revision it names." Measured, a `_meta` that is not a map (`"2025-11-25"`, `[]`, `7`, `null`) or that is a map without the version key does **not** match the clause head at `:127` and is served by the fall-through handlers instead — `ping` under such a `_meta` is answered. `FINDINGS.md:37-39` records the missing-key boundary; the non-map boundary is unrecorded and the comment reads as if the clause covered both. Unchanged from `base/main`; only the comment is new.

### 6. `PLAN.md:12-15` — a fetch dated one day in the future, and the fetch has no archive — note

```
$ date -I
2026-09-06
$ sed -n '12,15p' slices/001b-ping-guard/PLAN.md
**Every specification claim below was fetched on 2026-09-07 from …**
```
The date cannot have happened. Separately, the blockquotes at `PLAN.md:87-108` are the load-bearing evidence for the entire design decision, and no `logs/` file archives the fetch. `CONVENTIONS.md:77-79` permits citation-with-URL as always honest, so the *form* is allowed — but "fetched … not recalled" is an unverifiable process assertion, and `curl … | tee logs/spec-versioning.txt` would make it checkable at no cost. I could not verify the quotes independently.

### 7. `FINDINGS.md:84` cites a line number that is stale in the tree it ships with — note

It reads: the pre-existing test `(negotiation_test.exs:145)` was not edited. At `base/main` that was correct. In the reviewed index the diff inserts 15 lines above it, so the test is at `test/beam_mcp/negotiation_test.exs:160`, and line 145 is now `"1900-01-01"` inside the `-32022` test. The claim itself is true — I verified the test body is byte-identical across the diff — but a reader following the citation in the merged tree lands on a different test. Acceptance criterion 2 in `PLAN.md:170` has the same number; that one is defensible, since the PLAN was written pre-edit.

### 8. REUSE population: `.txt` is correctly outside, `.md` is an accidental gap — note

`tools/gate.sh:30` derives its population as `git ls-files -- '*.ex' '*.exs' '*.sh' '*.yml'`. The five new `logs/*.txt` files are **outside** it, and that is **correct**: an SPDX header prepended to a `tee`d archive would break `CONVENTIONS.md:73-79` — the bytes would stop being the command's bytes. The two rules are consistent.

The gap is `.md`. Six tracked `.md` files carry SPDX headers by convention, two do not (`FINDINGS.md`, `PLAN.md` at the repo root), and the gate cannot see either fact. This diff does not add a violation — `slices/001b-ping-guard/PLAN.md:1-4` and `FINDINGS.md:1-4` both carry headers — but the population is a hand-written extension glob under a comment that says "every tracked file that can carry a comment", which is the shape `CONVENTIONS.md:20-37` warns about. Out of scope here; worth filing.

Also at `tools/gate.sh:43`: `[ "$fail" -eq 0 ] && note "licence files" "pass"` — if any earlier step failed, the `licence files` line is **not printed at all**, so a reader following "read the step's line, not the exit code" gets a silently absent verdict rather than a failure. Not in this diff.

### 9. `-32022` echoes arbitrary attacker-supplied JSON — note, unchanged from base

`server.ex:339` puts `requested => version` verbatim into the error payload, and section A shows maps, lists and booleans echoed back. Reflection is to the same client only and the amplification is ~1×, so I am not calling it a defect; recording it because the new `_other` branch is where it now lives, and because a future change that logs or forwards that payload would inherit it. Byte-identical behaviour at `base/main`.

---

## Reproductions I ran (evidence integrity, item 5)

| archived log | my re-run | result |
|---|---|---|
| `logs/gate.txt` | `./tools/gate.sh` | **byte-identical**, all six lines `pass`, `exit=0` |
| `logs/green-negotiation.txt` | `mix test test/beam_mcp/negotiation_test.exs` | `12 tests, 0 failures`, `exit=0` (archive's extra `Compiling`/`Generated` lines are first-run noise) |
| `logs/full-suite.txt` | `mix test` | `36 tests, 0 failures`, `exit=0` |
| `logs/red.txt` | same test file against a `base/main` copy of `lib/beam_mcp/server.ex` in `<scratch>/r2/before/` | **reproduced**: `12 tests, 0 failures` → `12 tests, 2 failures`, `exit=2`, same two tests (`:167`, `:186`), same messages |
| `logs/probe-after.txt` | `mix run <scratch>/r2/probe_ping_repro.exs` | protocol bytes identical; version string `0.1.1` vs `0.1.2` — **finding 1** |

The `base/main` "before" measurement in `FINDINGS.md:25-32` and `:47-49`, `PLAN.md:30-37` and `:72-74`, and `CHANGELOG.md:23-26` all reproduce exactly against the copy, including `"version":"0.1.1"` in the modernised legacy result. `CHANGELOG.md:29-32`'s after-block reproduces exactly against the index.

The claim "Live in published `0.1.0`" (`FINDINGS.md:17`, `CHANGELOG.md:34`) is cited only to `5d8d1ae`, which is `main`, not the release. I checked the tag myself: `git show v0.1.0:lib/beam_mcp/server.ex` carries the same version-blind `cond` at its lines 98-108, and `git show v0.1.0:mix.exs` reads `@version "0.1.0"`. The claim is **true and under-cited** — no fetch of the Hex artifact backs it, only the tag, which I verified.

---

## What is not wrong

The `lib/` change is correct, minimal, and I found nothing to fix in it. The era switch is total, the two branches share one validation path, dispatch is unreachable before version acceptance, the recursion terminates by construction, and thirty malformed shapes produce no crash and no atom growth. Acceptance criteria 1-5 in `PLAN.md:167-174` are all met and I reproduced each. I am not raising a `lib/` finding, and I am not inventing one.

The three items I want changed are a stale evidence archive (1), a README claim contradicted by a one-command probe (2), and an unlabelled wire-visible removal in the changelog (3). All three are text, none touches `lib/`, and none requires a re-run of the test evidence.

**VERDICT: changes required**
