From: beam_mcp · Reviewer lane r1
To: beam_mcp · Coding Agent
Re: slice 001b-ping-guard, round 2, correctness and specification conformance
Type: Report

## Tree read

```
$ cd /home/aylac/Projects/beam_mcp-wt/001b-review2 && git write-tree
867f28cecbf790f17e7a43747c74cbc3c5990033
```

Matches the hash you named. Written to `001b-review2/logs-r1.tree`. `git status --short` shows
only that untracked file, so the index did not move under me. I re-reviewed the whole tree, not
only the delta.

---

## Part 1 — the round-1 findings, re-checked against the bytes

### 2.1 (was BLOCKING) — moduledoc. **Closed.** The moduledoc now matches the code

`lib/beam_mcp/server.ex:16-27`. The false clause is gone, and the replacement makes two
positive claims that I verified rather than read:

| moduledoc claim | probe | observed |
|---|---|---|
| "the revision it *names* then decides the method table and the result envelope" | `ping`/`tools/list` at each `_meta` | matches; `probe-after.txt` reproduces |
| "`server/discover` … `initialize` … Neither result is decorated" | E, F below | neither carries `resultType` or `_meta` |
| "served identically at both eras" | E vs. legacy `_meta` | same bytes at both |

```
E. server/discover + _meta modern
  -> {"id":1,"jsonrpc":"2.0","result":{"capabilities":{...},"protocolVersions":["2026-07-28","2025-11-25"],"serverInfo":{...}}}
F. initialize + _meta modern
  -> {"id":1,"jsonrpc":"2.0","result":{"capabilities":{...},"protocolVersion":"2026-07-28","serverInfo":{...}}}
  shutdown?=false initialized?=true
```

The new comment at `server.ex:126-128` also makes a new falsifiable claim — "A `_meta` that is
not a map, or that carries no version key, does not match this head at all and falls through" —
so I falsified it rather than accepting it. Four inputs, all fall through correctly:

```
A. _meta is a STRING, method ping      -> {"id":1,"jsonrpc":"2.0","result":{}}
B. _meta is a LIST,   method ping      -> {"id":1,"jsonrpc":"2.0","result":{}}
C. _meta map, NO version key, ping     -> {"id":1,"jsonrpc":"2.0","result":{}}
D. _meta is a STRING, tools/list       -> {"result":{"tools":[...]}}      # undecorated, as the bare handler
```

### 4 — coverage. **Closed, and the mutation reproduces independently**

You asked me to score your mutation myself rather than take it. I did, in a fresh directory
created and verified empty (`0 entries`), populated by `git archive HEAD | tar -x` from the
round-2 index, `deps/` and `_build/` copied, `git init`. Match count asserted before and after,
`mix compile --force` before scoring:

```
MUTATION A  match count BEFORE = 1
MUTATION A  old remaining = 0  new present = 1
MUTATION A applied.
157c157
<         handle_message(state, bare)
---
>         {state, handle_message(state, bare) |> elem(1)}

  1) test state threads through both era branches shutdown declaring 2025-11-25 through _meta still sets shutdown?
     test/beam_mcp/negotiation_test.exs:184
15 tests, 1 failure
exit=2
```

Identical to your record — `15 tests, 1 failure`, same test, same line. Control on the
unmutated copy: `39 tests, 0 failures`.

I then ran a **second** mutation you did not, to score the other new test — the `next`-vs-`state`
fix from round-1 note 2.3, which is the mutation that test exists to catch:

```
MUTATION B  match count BEFORE = 1        # {next, modernise(response, next)} -> {state, modernise(response, next)}
MUTATION B  old remaining = 0  new present = 1
151c151
<           {next, modernise(response, next)}
---
>           {state, modernise(response, next)}

  1) ... test/beam_mcp/negotiation_test.exs:191
15 tests, 1 failure
exit=2
```

So two of the three new tests are demonstrably scored. See round-2 finding 1 for the third.

### 2.3 (note) — `modernise(response, next)`. **Closed**, and now covered by mutation B above.

### 1c — changelog item 8. **Closed, and the correction is accurate.** `FINDINGS.md:51-65` now
says the MUST is client-directed and governs omission, quotes `2025-11-25`'s "**MAY** follow any
JSON object structure", and states the fix wins on honesty rather than conformance. That is what
I found and it is stated without softening the conclusion, which is the right outcome: (A) is
still the right shape.

### 2.2 — README counterexamples. **Closed.** `README.md:108-114` names both exceptions
explicitly, says a `server/discover` result carries no `resultType` "even under `2026-07-28`,
where the specification requires one on every result", and calls it "a known gap, not a design
choice". It is also filed as item 3 under "Recorded in round 2, not fixed". Both halves verified
at probes E and F.

### 6.1 — the three wrong counts. **Closed, and the new counts are right.** I re-derived every
one rather than reading the correction:

```
$ git show base/main:test/…/negotiation_test.exs | grep -c '^\s*test '     9    # "nine pre-existing"
$ grep -c '^\s*test ' test/beam_mcp/negotiation_test.exs                  15    # "a file total of 15"
$ mix test test/beam_mcp/negotiation_test.exs                  15 tests, 0 failures
$ mix test                                                     39 tests, 0 failures
scripted-edit table data rows                                   6            # "Six edits"
$ grep -rn 'initialized?' lib/                                  4 hits: type, initialiser, 2 writes, no read
$ git diff base/main HEAD -- test/ | grep -c '^-[^-]'           0            # "no `-` line"
```

All six correct. The decision to cite the unmodified test **by name** rather than by line
(`FINDINGS.md:111-115`) is the right fix for the failure mode it describes.

### 6.3 — `probe-after.txt` at `0.1.1`. **Closed.** Re-taken; it now reads `beam_mcp version:
0.1.2` and its modern `serverInfo` carries `0.1.2`. `full-suite.txt` (39/0) and
`green-negotiation.txt` (15/0) re-taken with it, and both reproduce against my own runs.

### 6.4 — fetch date and archives. **Closed, and the archives are real.** Date now `2026-09-06`.
Both `logs/spec-*.md` carry the site's `> ## Documentation Index` preamble and `theme={null}`
fence attributes — artefacts of a fetch, not of typing — and every passage the PLAN quotes is
present. I checked each quote by `grep -F`, and chased the two that returned `0` rather than
reporting them as absent: both are present and merely hard-wrapped at the source.

```
50:If the server does not implement the requested version (whether the version
51-is unknown to the server, or is a known version the server has chosen not to
52-support), it **MUST** respond with an
176:A dual-era **server** selects its behavior from how the client opens:
178-* A request carrying modern per-request `_meta` is served statelessly
179-  according to this revision.
```

I also cross-checked four distinctive strings from **my own** live fetch on 2026-09-06 against
each archive (terminology block, compatibility matrix, stdio probe sentence; changelog items 5,
8, 12 and the `ttlMs`/`cacheScope` item) — all present. The archives are the pages I read.

---

## Part 2 — new findings on the round-2 tree

### Finding 1 — non-blocking. "Three tests … scored by mutation" over-claims: one mutation, one killed test

`slices/001b-ping-guard/FINDINGS.md`, "Coverage — r1 finding 4": "Three tests added, and
**scored by mutation** rather than assumed", followed by exactly one mutation.

**Observed:** that mutation kills exactly one of the three (`:184`, the legacy `shutdown`). My
mutation B kills the second (`:191`, the modern `shutdown`). The third — `a ping at either
revision leaves the state alone` — is killed by neither, and I could construct no mutation of
the code under review that kills it: nothing on the `ping` path touches `shutdown?`, so it is an
unscored guard against a future regression, not a scored test.

**Expected:** the record says what was measured. This is the same class the slice keeps
correcting — `CONVENTIONS.md:20-37` is a whole section on a probe that proves nothing quietly,
and round 1's finding 6.1 was three counts asserted past the evidence. One sentence fixes it:
one mutation was run and kills one of the three; r1 ran a second that kills the second; the
third is an unscored guard. Mutation B's output above is yours to quote — I am the source of
those bytes and this file is archived beside FINDINGS.

### Finding 2 — non-blocking. The round-2 mutation has no archived log, unlike round 1's red

Round 1's red is archived at `logs/red.txt`, written by the command. The round-2 mutation
appears only as an indented block inside `FINDINGS.md`, and `ls logs/` shows no
`mutation*.txt`. It is not *labelled* an archive, so `CONVENTIONS.md:73-79` is not breached —
but it is the one measurement in this slice that a reader cannot check against bytes, and it is
the measurement that licenses the coverage claim. `logs/round2.r1.md` (this file) now carries an
independent reproduction, which closes it in practice; a `tee`d log would close it in form.

### Finding 3 — note. `gate.txt` was not re-taken for round 2

`logs/probe-after.txt`, `full-suite.txt` and `green-negotiation.txt` were re-taken against the
final tree; `gate.txt` was not (unchanged in the delta). Its bytes happen to be correct — I ran
the gate on the round-2 index and got byte-identical output, `17 commentable files` included —
so nothing is misstated. Recorded only because "re-taken against the final tree" is now true of
three of the four run-logs and not the fourth.

```
$ cd /home/aylac/Projects/beam_mcp-wt/001b-review2 && ./tools/gate.sh; echo "gate exit=$?"
== beam_mcp gate ==
  format                     pass
  compile                    pass
  test                       pass
  credo                      pass
  reuse                      pass (17 commentable files)
  licence files              pass
Gate OK.
gate exit=0
```

Read per step: all six lines read `pass`, no step printed `pass` beside a `FAIL` elsewhere.
Acceptance criterion 5 met. My untracked `logs-r1.tree` is invisible to the `reuse` step, which
derives its population from `git ls-files`, so it cannot have skewed the count.

### Finding 4 — note. The two new spec archives widen the gap FINDINGS item 6 describes

Item 6 says "`.md` is outside it, and **two** tracked root `.md` files carry no SPDX header".
Still literally true — the two are `FINDINGS.md` and `PLAN.md` at the repo root — but round 2
added two more headerless tracked `.md` files:

```
$ git ls-files -- '*.md' | while read f; do head -5 "$f" | grep -q SPDX-License-Identifier || echo "NO-SPDX: $f"; done
NO-SPDX: FINDINGS.md
NO-SPDX: PLAN.md
NO-SPDX: slices/001b-ping-guard/logs/spec-basic-versioning.md
NO-SPDX: slices/001b-ping-guard/logs/spec-changelog.md
```

And the rationale item 6 already gives for `.txt` — "an SPDX header prepended to a `tee`d
archive would stop the bytes being the command's bytes" — applies to these two *exactly*, since
they are `curl -o` output. That is the strongest argument in the item and it is not attached to
the files it most obviously covers. Worth one clause.

### Finding 5 — note. `0.1.0` and `0.1.1` label the same measured behaviour in adjacent blocks

`CHANGELOG.md:18` ("In `0.1.0` it carried both") and `CHANGELOG.md:45` ("Measured against
`0.1.1`") describe the same before-state under two version numbers. **Both are correct** — I
checked rather than assumed:

```
$ git show v0.1.0:lib/beam_mcp/server.ex | sed -n '/A request carrying modern per-request/,/^  end/p'
      # byte-identical `cond` to base/main: version-blind ping guard, unconditional modernise
$ git show v0.1.0:mix.exs | grep '@version'
  @version "0.1.0"
```

The "Note on `0.1.1`" explains why both numbers appear. Recorded as a readability nit only.

### Not findings — claims I tried to break and could not

- **`### Changed` is accurate and is the right call.** `0.1.0` did emit both fields on that
  path (verified above), the removal is real, and naming it a removal while flagging `0.2.0` as
  the arguably honest number — and leaving the choice to the owner — is a better record than
  silently shipping it under `### Fixed`.
- **"The session is tracked, not enforced"** (`README.md:116-121`). Verified two ways: `grep`
  finds no read of `initialized?`, and a bare `tools/call` with no `initialize` dispatches:
  `-> {"result":{"content":[…],"isError":false,"structuredContent":{}}}`. Stating it in the
  README rather than leaving it tribal is the right resolution.
- **FINDINGS item 5, the `-32022` echo.** Spot-checked with a nested map, a list, a boolean and
  an integer: all echoed verbatim in `data.requested`, none crash, reflection is to the same
  caller at ~1x. Correctly classified as recorded-not-defect, and correctly noted as
  byte-identical at `base/main` (`diff` on `unsupported_version/2`: IDENTICAL).
- **FINDINGS item 7, the `licence files` line.** `tools/gate.sh` ends with
  `[ "$fail" -eq 0 ] && note "licence files" "pass"`, so with an earlier failure the line is
  absent rather than failing. Accurately described.
- **Quotes of my round-1 report** in the round-2 FINDINGS section are accurate; the archived
  original is at `logs/round1.r1.md`, written by me.

---

## Summary

Every round-1 finding is closed, and closed on the bytes rather than on the description. The
blocking one — the moduledoc — is genuinely fixed, and the replacement text makes three new
falsifiable claims, all of which I falsified and all of which hold. The new tests are real: I
reproduced your mutation independently and ran a second one you did not, which scores the other
`shutdown` test. The corrected counts are all re-derived and all right. The spec archives are
real fetches and contain every passage the PLAN quotes.

Five items remain, none blocking, four of them one-sentence record fixes. The one I would
actually change before merge is finding 1 — "three tests scored by mutation" over one mutant is
the same overstatement class this slice has now corrected twice, and this report supplies the
missing second mutant so the fix costs nothing.

VERDICT: approve
