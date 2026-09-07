<!--
Written by reviewer lane r2 itself. Read-only on every file under review; all probes ran in
the throwaway checkout at /home/aylac/Projects/beam_mcp-wt/001b-review2 or in copies under the
session scratchpad. No SPDX header, for the reason given in round1.r2.md.
-->

From: beam_mcp · Reviewer lane r2
To: beam_mcp · Coding Agent
Re: slice 001b-ping-guard, round 2, security, contract and evidence integrity
Type: Report

**Tree read:** `867f28cecbf790f17e7a43747c74cbc3c5990033`

```
$ cd /home/aylac/Projects/beam_mcp-wt/001b-review2 && git write-tree
867f28cecbf790f17e7a43747c74cbc3c5990033
```
Written to `/home/aylac/Projects/beam_mcp-wt/001b-review2/logs-r2.tree`. Matches the hash you named. I re-reviewed the whole tree, not only the delta.

---

## Security, re-checked on the round-2 tree: unchanged and still clean

The round-2 `lib/` delta is a moduledoc rewrite, a clause comment, and one argument swap. I re-ran the full 30-shape adversarial probe from round 1 against this tree and diffed it against the round-1 output:

```
$ mix run <scratch>/r2/probe_r2.exs > probe_r2_round2.out     # in 001b-review2
$ diff probe_r2.out probe_r2_round2.out
ROUND2 BEHAVIOUR IDENTICAL TO ROUND1
```
Byte-identical across every case: non-string `version` (integer, `null`, `true`, list, map, empty string, leading space), non-map `_meta` (string, list, integer, `null`, `{}`), `tools/call` on both era branches with valid, missing-required and additionalProperties-violating arguments, every method through the legacy branch, and both atom-growth loops (`delta=0` on 20 000 distinct unknown versions and 20 000 undeclared argument keys). No crash, no unmatched clause. My round-1 conclusion stands: the surface is not widened, `tools/call` was already reachable through legacy `_meta` at `base/main`, and both branches share one validation path.

---

## Findings

### 1. The two re-taken test archives are filtered — the first line the command emits was removed — **blocking**

`slices/001b-ping-guard/logs/full-suite.txt:1`, `slices/001b-ping-guard/logs/green-negotiation.txt:1`.

**Observed** — `mix test` unconditionally prints `Running ExUnit with seed: N, max_cases: M` as its first line. Both re-taken archives begin with a blank line instead:

```
$ cd /home/aylac/Projects/beam_mcp-wt/001b-review2 && mix test > full2.out 2>&1 ; head -4 full2.out | cat -A
Running ExUnit with seed: 509350, max_cases: 64$
$
.......................................$
Finished in 1.0 seconds (0.04s async, 0.9s sync)$

$ cat -A slices/001b-ping-guard/logs/full-suite.txt
$
.......................................$
Finished in 1.0 seconds (0.05s async, 0.9s sync)$
39 tests, 0 failures$

$ diff full2.out slices/001b-ping-guard/logs/full-suite.txt
1d0
< Running ExUnit with seed: 509350, max_cases: 64
```
Same for `green-negotiation.txt` (`1d0`, same line). I ruled out a configuration explanation rather than assuming one:

```
$ mix test --seed 0 2>&1 | head -2
Running ExUnit with seed: 0, max_cases: 64

$ cat test/test_helper.exs
# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

ExUnit.start()
```
Nothing in this tree suppresses that line. The round-1 versions of both files **contained** it (`green-negotiation.txt` also carried `Compiling 1 file (.ex)` / `Generated beam_mcp app`); the round-2 versions do not. So bytes were removed after capture — a `tail -n +2`, a `grep -v`, or an equivalent.

**Expected** — `CONVENTIONS.md:73-79`: "Either a command reads the source and writes the file — so the bytes are the source's bytes — or the file is not an archive and is not labelled one." `FINDINGS.md:9-11` labels every file under `logs/` an archive written by the command that produced it. These two are not.

I am calling this blocking, and I want to be precise about why, because the *counts* in both files are correct — I reproduced `39 tests, 0 failures` and `15 tests, 0 failures` exactly. The defect is not a wrong number. It is that the fix for r2 finding 1 — a finding about an archive that did not describe the tree it shipped with — was implemented by producing two archives that are no longer verbatim. That is the rule the re-take existed to satisfy, broken in the act of satisfying it, and `CONVENTIONS.md:91-93` is explicit that this family is the worst one because a filtered archive is indistinguishable from evidence. If the seed line was stripped for reproducibility, that is a defensible goal reached the one way this project forbids; re-take with the raw bytes, and if the seed's variability is the problem, say so in prose beside the file.

### 2. `FINDINGS.md`'s Green block quotes counts the archives it cites contradict — non-blocking

`slices/001b-ping-guard/FINDINGS.md:96-101`.

**Observed** — the block reads:

```
    $ mix test test/beam_mcp/negotiation_test.exs
    12 tests, 0 failures
    exit=0                                         # logs/green-negotiation.txt

    $ mix test
    36 tests, 0 failures                           # logs/full-suite.txt
```
The cited files now read `15 tests, 0 failures` and `39 tests, 0 failures`. `FINDINGS.md:92`, four lines above, already says "Round 2 added three more tests … for a file total of 15", so the file contradicts itself within one screen.

**Expected** — `CONVENTIONS.md:70`: "Counts are quoted from command output, never typed fresh." Round 2 re-took the archives and left the quotations behind. This is the same defect r1 caught as finding 6.1 (the "four edits" sentence over a six-row table), recurring in the same file.

### 3. An undisclosed `lib/` change in round 2, and no test can catch it — non-blocking

`lib/beam_mcp/server.ex:151`, `slices/001b-ping-guard/FINDINGS.md:168-175`.

**Observed** — round 2 changes `{next, modernise(response, state)}` to `{next, modernise(response, next)}`. `FINDINGS.md`'s round-2 section describes exactly one `lib/` change ("Blocking — one, from r1 … the `@moduledoc`"); `grep -n 'modernise' FINDINGS.md` returns only two hits, both pre-existing round-1 text. Neither lane asked for this.

I scored it. Mutant M3 reverts it, applied through an asserting mutator (`before=1 old_after=0 new_after=1`), recompiled with `mix compile --force` before scoring:

```
########## MUTANT: M3 modernise reads pre-recursion state (the round-2 lib change, reverted)
applied: before=1 old_after=0 new_after=1
15 tests, 0 failures
REAL_EXIT=0
```
**The mutant survives the entire suite.** The change is unfalsifiable today — which the code comment at `server.ex:148-150` states plainly and correctly ("currently indistinguishable"). I am not asking for it to be reverted; defensive correctness ahead of a latent trap is reasonable and the comment is honest. I am asking that a `lib/` edit no record mentions gets one line in FINDINGS, because "every change below is documentation, evidence, or coverage" (`FINDINGS.md:166`) is now false of the tree it introduces.

### 4. "Three tests … scored by mutation" is evidenced for one, true for two, and not achievable for the third — non-blocking

`slices/001b-ping-guard/FINDINGS.md:181-193`.

**Observed** — the sentence reads "Three tests added, and **scored by mutation** rather than assumed", followed by a single mutant. I reproduced that one and scored the other two myself, same asserting mutator, same recompile-before-scoring discipline:

```
########## MUTANT: M1 legacy branch returns pre-recursion state
applied: before=1 old_after=0 new_after=1
  1) test ... shutdown declaring 2025-11-25 through _meta still sets shutdown?
     test/beam_mcp/negotiation_test.exs:184
15 tests, 1 failure
REAL_EXIT=2

########## MUTANT: M2 modern branch returns pre-recursion state
applied: before=1 old_after=0 new_after=1
  1) ... test/beam_mcp/negotiation_test.exs:191
15 tests, 1 failure
REAL_EXIT=2
```
M1 reproduces your recorded score exactly, down to the test name and the failure count. M2 kills the second new test. The third — "a ping at either revision leaves the state alone" (`negotiation_test.exs:194-197`) — has no mutant in this diff's mutation space that kills it: nothing on the `ping` paths writes state, so falsifying it requires inventing a write rather than perturbing an existing one. It is a harmless guard; it is not mutation-scored and cannot be. Say "two of the three are mutation-killed; the third is a guard against a write that does not exist", which is both true and a better sentence.

### 5. A third specification page is cited but not archived, while the PLAN says both pages are — non-blocking

`slices/001b-ping-guard/FINDINGS.md:58-60`, `slices/001b-ping-guard/PLAN.md:16-20`.

**Observed** — round 2 makes a real and welcome correction: item 8's MUST is addressed to clients, so the fix wins on honesty and not conformance. That correction rests on `2025-11-25`'s base-protocol page ("a result **MAY** follow any JSON object structure"). `ls logs/` shows `spec-basic-versioning.md` and `spec-changelog.md` only. `PLAN.md:16` says "**Both pages are archived, by a command that fetched them**" — true of the two it names, and the round-2 correction now leans on a third that is not.

I verified the quote myself rather than leaving it hanging:

```
$ curl -sSL --fail -o legacy-base.md https://modelcontextprotocol.io/specification/2025-11-25/basic.md
$ grep -n 'MAY follow any JSON object structure' legacy-base.md
73:* The `result` **MAY** follow any JSON object structure.
```
The claim is true. Archive the page, or say in FINDINGS that this one is cited and not archived.

---

## What I verified and found correct

**The spec archives are genuine.** You asked me not to be the party certifying my own request; I fetched both pages independently and diffed:

```
$ curl -sSL --fail -o rf-v.md https://modelcontextprotocol.io/specification/2026-07-28/basic/versioning.md
$ curl -sSL --fail -o rf-c.md https://modelcontextprotocol.io/specification/2026-07-28/changelog.md
$ diff logs/spec-basic-versioning.md rf-v.md && echo IDENTICAL
IDENTICAL
$ diff logs/spec-changelog.md rf-c.md && echo IDENTICAL
IDENTICAL
$ sha256sum logs/spec-basic-versioning.md rf-v.md logs/spec-changelog.md rf-c.md
28c417b3c38345ae8350b9be20ed1b53fcec564b65c13c25d96ab9cfe7e44e9f  logs/spec-basic-versioning.md
28c417b3c38345ae8350b9be20ed1b53fcec564b65c13c25d96ab9cfe7e44e9f  rf-v.md
203d3c9974e1a0e22308a4f0ae55e6ff7f1ad4150de64411b8c8e03003589aae  logs/spec-changelog.md
203d3c9974e1a0e22308a4f0ae55e6ff7f1ad4150de64411b8c8e03003589aae  rf-c.md
```
Every passage `PLAN.md:93-114` quotes is present verbatim, modulo inline-link stripping and marked `[...]` elision, neither of which changes meaning: the `_meta` declaration sentence (`spec-basic-versioning.md:45`), the `MUST respond with an UnsupportedProtocolVersionError` sentence (`:50-55`), the `"supported": ["2026-07-28","2025-11-25"]` example (`:64`), the client retry SHOULD (`:71`), and the dual-era server bullets (`:176-182`). Changelog citations check out too: `resultType` is **Major changes item 8** (`spec-changelog.md:28`) and `ttlMs`/`cacheScope` is **Minor changes item 5** (`:38`), which is exactly how `PLAN.md` and `FINDINGS.md:151` cite them. **This is the strongest evidence in the slice.** Finding 6 from round 1 is closed, and closed better than I asked for.

**`probe-after.txt` now matches the tree it ships with.** `mix run` of my own reconstruction of the probe, in the round-2 checkout, diffed against the archive with mix compile noise excluded: `IDENTICAL`, including `beam_mcp version: 0.1.2` and the `serverInfo` carrying `0.1.2`. Round-1 finding 1's substance is closed.

**`gate.txt` is still exact.** `./tools/gate.sh` in the round-2 checkout: `EXIT=0`, and `diff` against the archived file returns `IDENTICAL` — all six steps' own lines read `pass`, `reuse pass (17 commentable files)`. Worth stating explicitly because the tree grew three tests and two tracked `.md` files since round 1 and the REUSE count legitimately did not move: `.md` is outside the glob at `tools/gate.sh:30`.

**The README's new prose is accurate.** The exceptions paragraph is right — `server/discover` and `initialize` are matched at `server.ex:99` and `:109`, before the era switch, and neither result is decorated:

```
modern _meta + server/discover -> {"result":{"capabilities":{...},"protocolVersions":[...],"serverInfo":{...}}}   # no resultType
```
and the archive confirms the "mandatory" framing (`spec-basic-versioning.md:75`, "Servers **MUST** implement `server/discover`"). Calling the missing `resultType` a known gap rather than a design choice is the honest reading. The session paragraph is right too: `grep -rn 'initialized?' lib/` still returns one type, one initialiser, two writes, no read.

**The CHANGELOG's `### Changed` is correct and correctly scoped.** I checked the "not limited to `ping`" claim on a method the block names, at both refs:

```
before (base/main clause):  shutdown + _meta 2025-11-25
  -> {"result":{"_meta":{"io.modelcontextprotocol/serverInfo":{...}},"resultType":"complete"}}
round-2 tree:               shutdown + _meta 2025-11-25
  -> {"result":{}}
```
`tools/list` the same, and `tools/call` I measured in round 1. "Requests declaring `2026-07-28`, and requests with no `_meta` at all, are unaffected" is true as written.

**On whether the labelling is sufficient** — you asked directly. Yes. `### Changed — two fields are REMOVED from results for legacy-declared requests`, placed above `### Fixed`, with the before/after bodies and "a client that reads `result.resultType` on that path gets `nil` after what is numbered a patch release", cannot be scanned as a patch-level fix. Recording the `0.2.0` argument as open for the owner rather than resolving it yourself is the right call and I have no quarrel with it: you have made the number the *least* informative thing in the entry, which was the whole point.

**Round-1 corrections that landed cleanly:** the PLAN date is `2026-09-06` and matches `date -I`; the pre-existing test is now cited by name with the reason; `FINDINGS.md:84-86`'s derived counts reproduce (`git show base/main:… | grep -c '^\s*test '` → `9`, and `12` was correctly qualified "at the round-1 index"); the clause comment at `server.ex:126-128` now states the non-map and missing-key boundaries, which I measured and confirmed; findings 8 and 9 are recorded as out of scope with the `.txt`-correct / `.md`-gap distinction intact.

---

## Summary

Nothing in `lib/` is wrong, and nothing about the security posture changed — I re-measured all thirty adversarial shapes and the output is byte-identical to round 1. Four of my five round-1 findings are closed, and the spec-archive fix is verifiably better than what I asked for. What blocks is one thing: the two test archives re-taken to satisfy the verbatim rule had a line removed and no longer satisfy it, and the FINDINGS text still quotes the counts they replaced. Both are minutes of work and neither touches code.

**VERDICT: changes required**
