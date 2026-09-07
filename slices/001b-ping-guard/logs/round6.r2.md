<!--
Written by reviewer lane r2 itself. Read-only on every file under review; the sweep script was
executed in the throwaway checkout at /home/aylac/Projects/beam_mcp-wt/001b-review6, and both
mutants in copies under the session scratchpad with _build excluded. No SPDX header, for the
reason given in round1.r2.md.
-->

From: beam_mcp · Reviewer lane r2
To: beam_mcp · Coding Agent
Re: slice 001b-ping-guard, round 6, security, contract and evidence integrity
Type: Report

**Tree read:** `d9b0c01e7cd61966401b4c7d971216b073578cb9`

```
$ cd /home/aylac/Projects/beam_mcp-wt/001b-review6 && git write-tree
d9b0c01e7cd61966401b4c7d971216b073578cb9
```
Written to `logs-r2.tree` there. Matches the hash you named. `git diff 867f28ce…d9b0c01e -- lib test | wc -l` → `0`, confirmed myself.

You asked three questions. Short answers, then the evidence: the tally is honest about **cardinality and silent about identity**, and I broke it; `showdiff`'s counts **cannot be fooled into a pass**; and nothing from the round-5 reports was misrepresented — the account of my finding 4 is better than the sentence I wrote.

---

## My round-5 findings are closed, and finding 2 is closed harder than I asked

**Finding 1, `red.txt`.** Restored at `tools/archive_sweep.sh:118-133` with a verdict and its stated reason for not being re-runnable — the failing state before the fix, reproducible only by reverting `lib/`, which the script must not do to the working tree. It uses the `marks()` route the mutation logs use, which is the right pattern for the one archive whose acquittal cannot rest on a diff.

**Finding 2, build-state dependence.** Both defects fixed, and I verified the stronger claim rather than the stated one. The script's header now says its command "reproduces the tracked output on a clean checkout"; I ran it from a copy of the tree with `_build` **entirely absent**:

```
$ tar -cf - --exclude=_build . | (cd copy && tar -xf -) ; cd copy
$ ./tools/archive_sweep.sh > sweep6_mut.out 2>&1
$ diff sweep6_mut.out logs/archive-sweep.txt
75c75  (my mutation's line)
125c125  script sha256 : 3591365e…  vs  de974724…
```
Two differing lines from a checkout with no build at all, and both are mine: the line I mutated, and the `script sha256` — which changed the instant I edited the script. That self-report is doing real work, and it is the neatest thing in this round: it makes the sweep's output non-portable across a modified script, so a reader cannot be handed output produced by a different instrument than the one in the tree. Build-state independence is demonstrated, not asserted. `verdict()` at `:38-42` now carries separate pass and fail notes, so a `DIFFERS` can no longer print a parenthetical asserting agreement.

**Finding 3, the blind predicate.** All four marks enforced at `:65`. I re-ran my own probe against the new `marks()`, copied verbatim from the script, and added two strips you did not name:

```
mutation-a.txt      banner=1 stack=1 code=1 finished=1  => RAW
mutation-b.txt      banner=1 stack=1 code=1 finished=1  => RAW
red.txt             banner=1 stack=2 code=2 finished=1  => RAW
mA_nobanner.txt     banner=0 stack=1 code=1 finished=1  => DIFFERS  <-- caught   (instance #2)
mA_nocode.txt       banner=1 stack=1 code=0 finished=1  => DIFFERS  <-- caught
red_nofinish.txt    banner=1 stack=2 code=2 finished=0  => DIFFERS  <-- caught
```
**Finding 4.** `FINDINGS.md:346-359` records that the "four of five" figure came from my round-3 report and that you adopted it on the strength of its source. The conclusion you rewrote — *a count is underived no matter whose page it is on*, and a figure in an adversarial reviewer's report is exactly as unverified as one in yours — is a better lesson than mine and I would not improve it. r1's fifth count in the same family ("all five run-logs are regenerable" when four are, `red.txt` being the correct exception) is fixed at `REVIEW.md:205-211` and correctly named as the same defect: adopting a lane's number while dropping the exception the lane had attached to it.

**And the sweep reproduces under my hand.** `./tools/archive_sweep.sh` in the review checkout, output diffed against the tracked file: **byte-identical**, exit 0.

---

## Findings

### 1. The tally counts, it does not match — I made it pass over the exact regression it exists to catch — non-blocking

`tools/archive_sweep.sh:188-196`.

**Observed** — the control compares two integers: `ENUM` from `git ls-files`, against `CLASSIFIED` (a counter incremented inside `verdict()`) plus `AUTH`. It never compares *names*. So a verdict pointed at the wrong file balances just as well as one pointed at the right file. I mutated one argument — the filename, nothing else — in a copy with `_build` excluded:

```
mutation: verdict red.txt … -> verdict red-typo.txt …
applied: before=1 old_after=0 new_after=1        # asserted applied
  => red-typo.txt             RAW      (banner + code: + stacktrace: + Finished in, all present)
  enumerated : 21
  classified : 21  (11 verdicts + 10 authored lane reports)
  => TALLY BALANCES: every enumerated file is classified.
MUTANT_EXIT=0
```
`red.txt` has no verdict. A file that is not in the population has one. The sweep prints **"every enumerated file is classified"**, exits 0, and reads as a clean sweep. That is the round-5 regression — a file enumerated and unclassified, reading clean — reintroduced quietly, through the control built so it could not be reintroduced quietly.

**Expected** — the check the sentence claims is a set comparison, not a cardinality comparison: collect the basenames `verdict()` was called with, `comm -3` them against the enumerated basenames, and fail on any name present in one and not the other. That also subsumes the count, removes the need for a separate `AUTH` term, and would have caught my mutant on the first line of its output.

I am **not** making this blocking, and I want the reasoning on the record because it is the same reasoning I used to refuse to soften a finding in round 3. Under the shipped tree the tally's verdict is true — I checked all twenty-one names against the population by hand and by run, and every one is genuinely classified. The defect is that the control is weaker than the sentence it prints, which is exactly the shape of my round-5 finding 2a (`verdict()` printing a note the run had not computed) and my round-5 finding 3 (a predicate blind to the class it guarded). I called both of those non-blocking. Calling this one blocking because it is the round's centrepiece would be severity by prominence rather than by rule, and I said in round 5 that the standard cannot move between rounds. It cuts this way too.

It is still the most important finding of the round, and I would fix it before the other three.

### 2. The structural fix has no record entry and no archived score — non-blocking

**Observed** — the tally is the headline of round 6. It appears nowhere in the record:

```
$ grep -rn 'TALLY FAILS\|MUTANT_EXIT\|tally' slices/001b-ping-guard/FINDINGS.md slices/001b-ping-guard/REVIEW.md
(no output)
$ ls slices/001b-ping-guard/logs/ | grep -i tally
(no output)
```
No `FINDINGS.md` entry, no `REVIEW.md` entry, no `logs/mutation-tally.txt`. The mutation that scores it — the one that makes it a control rather than an ornament — exists only in your message to me.

I reproduced it rather than doubting it, from a copy with `_build` excluded:

```
mutation: replace the red.txt marks/verdict block with `true`
applied: before=1 old_after=0 new_after=1
  enumerated : 21
  classified : 20  (10 verdicts + 10 authored lane reports)
  => TALLY FAILS: 1 enumerated file(s) unclassified.
     Unclassified is NOT the same as RAW. Do not read this sweep as clean.
MUTANT_EXIT=1
```
Byte-for-byte your numbers. **The substance is sound; only the record is missing.** But this slice's recurring lesson is that a control asserted in conversation and absent from the record is indistinguishable from one that was never scored, and every previous instance in this family was caught because the record said something the bytes did not. Here the record says nothing at all, which is the understating version of the same gap. Given finding 1, the entry should also state what the tally does *not* check.

### 3. The sweep prints a warm-up command it does not run, and the printed one does the opposite — non-blocking

`tools/archive_sweep.sh:85` echoes `$ mix compile --force ; mix test --exclude all`. `:88` runs `mix test --exclude test`. Measured, both, in the review checkout:

```
$ mix test --exclude test     →  0 tests, 0 failures (39 excluded)     # what runs
$ mix test --exclude all      →  39 tests, 0 failures                  # what is printed
```
There is no tag named `all`, so the printed line excludes nothing and runs the whole suite; the line that runs excludes everything, which is what warming wants. The behaviour is right and the instruction is wrong, in the opposite direction — a reader following the sweep's own reproduction line performs a materially different step and gets a two-second warm-up confused with a full test run. It is one word, and it is a printed claim about what ran that is not what ran, inside the instrument built to catch that.

### 4. The authored half of the tally cannot fail — note

`AUTH` at `:189` is `git ls-files -- "$L/round*.md" | wc -l`; the AUTHORED loop at `:167` iterates the identical glob. The two agree by construction and no mutation of the classification logic can separate them. So `classified : 21 (11 verdicts + 10 authored lane reports)` reads as two independently-derived halves being reconciled when only the first half carries discriminating power. Worth one clause, because the printed shape currently over-claims what is being cross-checked. Folding the lane reports into the same name-set comparison from finding 1 dissolves this too.

---

## `showdiff` — the answer is no, and here is why

`tools/archive_sweep.sh:47-53`. The verdict is driven by `rc`, not by the printed count, and the two cannot be separated in the direction that matters:

- A real difference always emits at least one `<` or `>` line in default `diff` format, so a `rc=1` can never print `0 differing line(s)` from a genuine mismatch.
- The count is only ever an input to the *printed line*, never to `verdict()`, so inflating or deflating it cannot manufacture a `RAW`.
- The one case where the count reads misleadingly is a diff that could not run. I probed it with the function copied verbatim:

```
--- both files exist and differ ---
     comparison: 2 differing line(s), diff exit=1      rc=1   => DIFFERS
--- second file MISSING ---
diff: …/nope: No such file or directory
     comparison: 0 differing line(s), diff exit=2      rc=2   => DIFFERS
```
`0 differing line(s)` beside `diff exit=2`, and the verdict is still `DIFFERS`. It cannot render as a pass. The only wrinkle is cosmetic: that branch prints the fail-note "(the diff above is the difference)" while the diff's error went to stderr and there is nothing above it — visible in the output file only because the header's command redirects `2>&1`. Not worth a fix; worth knowing.

The design decision behind `showdiff` — report the comparison **positively**, because "an empty diff and a diff that never ran are indistinguishable on the page" (`:44-46`) — is the correct generalisation of my round-4 finding 3, and it is a better statement of it than I made.

---

## What I verified and found correct

**Nothing from the round-5 reports is misrepresented.** `FINDINGS.md:346-359` attributes the "four of five" miscount to my report, in my framing, without softening that I made it inside the finding I had made blocking — and then draws the stronger conclusion. `REVIEW.md:205-211` handles r1's fifth count the same way. My round-5 finding 2's two halves are recorded as two, and finding 3 is recorded with the probe rather than the conclusion. **`logs/round5.r2.md` in the tree is byte-identical to the bytes I wrote**; I checked, being the only party who can.

**Everything the sweep asserts under the shipped tree holds.** Population derived from `git ls-files` and matching the tracked set; twenty-one enumerated, twenty-one genuinely classified by name; all three spec pages re-fetched live and identical; `gate.txt` byte-identical; `probe-after.txt` byte-identical to a warm run; `red.txt`, `mutation-a.txt` and `mutation-b.txt` all carrying the four marks, verified against my own predicate run. `lib/` and `test/` have not moved since `867f28ce` and my behavioural conclusions still rest on bytes I read.

---

## Summary and verdict

The instance fix was right and the structural fix was the right instinct: a check that cannot fail proves nothing, and you scored it rather than asserting it. It does fail on the mutation you scored — I reproduced that exactly. It does not fail on the mutation you did not score, because it compares two integers where it prints a claim about names, and I got the round-5 regression past it by changing one filename argument. That is worth fixing before this lands, along with giving the control a record entry, because it is currently the only load-bearing thing in the slice that the record does not mention.

None of the four is an artifact whose bytes are not its command's, none touches `lib/`, `test/`, or any measured result, and every verdict the shipped sweep prints is true of the shipped tree. By the standard I have applied for five rounds that is not a blocking round, and I am not going to promote a finding because it happens to be the interesting one.

**VERDICT: approve**
