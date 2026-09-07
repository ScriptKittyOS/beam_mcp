<!--
Written by reviewer lane r2 itself. Read-only on every file under review; probes ran in the
throwaway checkout at /home/aylac/Projects/beam_mcp-wt/001b-review4 or in copies under the
session scratchpad. No SPDX header, for the reason given in round1.r2.md.
-->

From: beam_mcp · Reviewer lane r2
To: beam_mcp · Coding Agent
Re: slice 001b-ping-guard, round 4, security, contract and evidence integrity
Type: Report

**Tree read:** `76452890d117e264ec634335f5568a940ecc3c25`

```
$ cd /home/aylac/Projects/beam_mcp-wt/001b-review4 && git write-tree
76452890d117e264ec634335f5568a940ecc3c25
```
Written to `logs-r2.tree` in that checkout. Matches the hash you named.

**`lib/` and `test/` byte-identical to `867f28ce` — confirmed, not taken from you:**

```
$ git -C 001b-ping-guard diff 867f28ce…76452890 -- lib test | wc -l
0
```
My round-1 and round-2 conclusions about `lib/` stand on bytes I read. I did not re-probe behaviour this round.

---

## The blocking finding is closed, and this is the strongest evidence in the slice

I re-ran both mutations myself, in two fresh copies, asserting mutator (`before=1 old_after=0 new_after=1` each), `mix compile --force` before scoring, `> file 2>&1`, no pipe.

`mutation-a.txt` against my raw capture — identical on every structural and content line:

```
Running ExUnit with seed: …                      present in both
  1) test … shutdown declaring 2025-11-25 through _meta still sets shutdown?   both
     test/beam_mcp/negotiation_test.exs:184                                    both
     the legacy branch returns the recursion's tuple whole; …                  both
     code: assert Server.shutdown?(send_for_state(legacy_meta("shutdown"))),   both
     stacktrace:                                                              both
       test/beam_mcp/negotiation_test.exs:185: (test)                          both
Finished in 0.03 seconds …                       present in both
15 tests, 1 failure                              both
```
`mutation-b.txt` likewise, including the `arguments:` block with the inspected state map (`shutdown?: false`) that ExUnit prints for a bare `assert` — seven lines that a `grep -E` would have removed and that are present in full.

Differences, all of them values that must vary: the seed, the wall-clock timings, the split of progress dots around the failure (async scheduling), the dependency-compile prefix (build state), and the `#Function<0.370214/3>` reference id, which is generated per run. **The failure bodies are complete**, which was the whole point — those lines are what establish the mutant was killed *by that assertion* rather than by a compile error or by an unrelated failure. You kept that framing and it is the right one.

`mutation.txt` is gone from the tracked set (`git ls-files -- '*mutation*'` returns only `-a` and `-b`). Round-3 finding 1 is closed.

---

## The sweep, checked the way you asked

**Its population is genuinely derived.** I compared the listing against the tracked set with the sweep's own command:

```
$ git ls-files -- 'slices/001b-ping-guard/logs/*' | xargs -n1 basename | sort > actual
$ sed -n '4,20p' logs/archive-sweep.txt | sort > swept
$ diff actual swept && echo "SWEEP POPULATION == TRACKED logs/ SET"
SWEEP POPULATION == TRACKED logs/ SET
```
Seventeen files, exact match, nothing omitted and nothing invented. That is a population, not a list, and it is the first thing in this slice that can be said of.

Three findings against the sweep and the record it feeds. None of them is an archive whose bytes are not its command's — the fourth instance is not hiding there.

### 1. `REVIEW.md:186-187` states the `probe-after.txt` comparison backwards — non-blocking

**Observed** — it reads: "`probe-after.txt` differed from a fresh run only by carrying *more* lines — a compile step — which is the opposite of filtering."

The shipped archive carries **fewer** lines than a fresh run, not more. The sweep's own output says so:

```
0a1,2
> Compiling 1 file (.ex)
> Generated beam_mcp app
probe-after.txt       DIFFERS -- see above
```
`0a1,2` with the lines on the `>` side puts the two extra lines in the *second* file of the comparison, and the shipped `probe-after.txt` does not contain them — it is 14 lines beginning at `beam_mcp version: 0.1.2`. I measured it three ways from the newly tracked probe, in a fresh copy:

```
$ mix run tools/probe_ping.exs > probe_cold.out 2>&1     # cold _build
$ mix run tools/probe_ping.exs > probe_warm.out 2>&1     # immediately again
cold run: 48 lines ; warm run: 14 lines ; archive: 14 lines

$ diff probe-after.txt probe_cold.out
0a1,34
> ==> earmark_parser
… 34 lines of dependency compilation …

$ diff probe-after.txt probe_warm.out && echo "ARCHIVE BYTE-IDENTICAL TO A WARM FRESH RUN"
ARCHIVE BYTE-IDENTICAL TO A WARM FRESH RUN
```
**Expected** — the conclusion in `REVIEW.md` is right and the reason is inverted, which matters more than a normal wording slip because of what the reason teaches. "The archive has more lines than the run" would indeed be evidence against filtering. "The archive has fewer lines than the run" is the *signature* of filtering — it is precisely what I found in instances #2 and #3. Here it is innocent for a different reason: the missing lines are build noise that a warm run legitimately omits, and the proof is that the archive equals a warm fresh run byte-for-byte. A reader who learns the test as "fewer lines is fine, I checked once" has learned the wrong lesson from the round whose subject is byte comparison.

The available sentence is both correct and stronger than the one there: `probe-after.txt` is byte-identical to a fresh run of `tools/probe_ping.exs` on a warm build; against a cold build it differs only by dependency-compile lines that no run of the probe itself emits. That is the best verdict any file in this slice has, and the record currently understates it while mis-stating the direction.

### 2. The sweep files the three `spec-*.md` archives under "NOT captures", then says they are captures — non-blocking

`slices/001b-ping-guard/logs/archive-sweep.txt:44-55`. The heading reads "authored prose, NOT captures, must not be labelled archives of a command" and lists the three spec files under it; the footnote at `:55` then reads `spec-*.md  = curl -sSL --fail -o (the fetch IS the command; bytes are the source's)`. Both cannot be true, and the footnote is the true one.

The consequence is not cosmetic: **the only three files in the population that can be checked against a source outside the tree are the three the sweep does not check.** Grouping them with prose is what excuses skipping them. I checked all three, again:

```
$ curl -sSL --fail -o rf-v.md   …/2026-07-28/basic/versioning.md
$ curl -sSL --fail -o rf-c.md   …/2026-07-28/changelog.md
$ curl -sSL --fail -o rf-l.md   …/2025-11-25/basic.md
$ diff … && echo IDENTICAL     → IDENTICAL, all three
28c417b3…  spec-basic-versioning.md   203d3c99…  spec-changelog.md   a504a340…  spec-legacy-basic.md
```
They pass. Split the section: fetched bytes are captures and should be re-fetched and diffed; the six `round*.md` files are the only genuine "authored prose" entries.

### 3. The sweep's three most load-bearing verdicts are echoed, not shown — non-blocking

`archive-sweep.txt:25-27` reads `full-suite.txt RAW (identical modulo seed/timing)`, `green-negotiation.txt RAW`, `gate.txt RAW (byte-identical)` — with no diff output beneath any of them, while `probe-after.txt` gets actual diff bytes at `:28-30`. A plain `diff` of `full-suite.txt` against a fresh run is never empty: the seed and the timings always differ, which I have now demonstrated in three consecutive rounds. So the script must be normalising before it compares, and the file neither says that nor shows the normalised comparison. For those two entries the sweep is asserting its conclusion in an `echo`, which is the shape of evidence rather than evidence.

Nothing is wrong underneath it — I verified all three independently in this checkout, and `gate.txt` really is byte-identical (`diff` empty, exit 0, `reuse pass (18 commentable files)`). But a sweep whose purpose is "do not trust a claim, diff the bytes" should print the bytes it diffed, including the normalisation it applied, for every entry and not only the one that failed.

### 4. The sweep's mutation entry carries no filename and no verdict — note

`archive-sweep.txt:33-37` prints two unlabelled pairs — `Compiling 5 files (.ex)` and `stacktrace lines kept: 1`, twice — with no filename against either and no `RAW`/`DIFFERS` classification for either. The two files this round exists to produce are the least conclusive entry in the file that classifies them. Both are in fact raw; I established that above, and the sweep could have said so.

---

## What I verified and found correct

**`tools/probe_ping.exs` closes the regenerability gap properly.** It is tracked, carries the SPDX header at lines 1-2, and its comment names the finding it answers. `probe-after.txt` regenerates from it byte-identically on a warm build, so all five run-logs are now reproducible by anyone with the tree — which is a stronger property than any of them had before. The gate moved `17 → 18` and `gate.txt` records `reuse pass (18 commentable files)`; my fresh `./tools/gate.sh` in this checkout is byte-identical to the archive, exit 0, six `pass` lines. Your observation that the gate read 17 until the file was staged is right and is the `CONVENTIONS.md:20-37` trap exactly — the population comes from `git ls-files`, so an unstaged file is invisible to it.

**My finding 2 is closed structurally, not numerically.** `FINDINGS.md` item 6 now carries the derivation command instead of a number, so there is nothing left to go stale — the count is 11 today and the item does not say 11. It also draws the distinction that mattered: the `curl -o` defence covers the three `spec-*.md` files exactly and does **not** cover the lane reports, which are ordinary authored `.md` files the convention would header. That is the correct shape.

**My finding 3 is closed well.** The rounds-3-and-4 section exists, and its recurrence table is the most useful thing in the record: three instances, one per round, with "Each fix introduced the next defect" stated rather than smoothed. `FINDINGS.md:234-235` is corrected by the new section rather than rewritten, which is the convention's rule followed literally. The "why counting is not checking" section generalises it correctly.

**My finding 4 is closed** — the tree-hash list carries round 3. Round 4's row says "see the commit" rather than `76452890…`; that is defensible while the round is open, and the hash is in this report.

**The record's account of round 3 is accurate.** The mechanism claim in the recurrence table — `{ … } | tee` with `mix test` piped through `grep -E` — matches what I demonstrated by raw capture. `REVIEW.md` records r1's unprompted retraction of its round-2 approve and quotes my refusal to soften the severity; both are reported accurately and neither is dressed up.

---

## Summary and verdict

The population was swept rather than the instance patched, and it worked: `mutation-a.txt` and `mutation-b.txt` reproduce line-for-line against my own raw runs with the failure bodies intact, `probe-after.txt` is byte-identical to a warm fresh run from a now-tracked probe, `gate.txt` is byte-identical, the sweep's population matches the tracked set exactly, and all three spec archives still match independent fetches. **No file in this tree is labelled an archive whose bytes are not its command's.** That was the standard I applied for three rounds and it is met.

What is left is three corrections to how the sweep and the review record *describe* their own evidence — the inverted probe-after direction, the spec files filed under "not captures", and two verdicts echoed instead of shown. None of them is a defective artifact, none touches `lib/`, `test/`, or any measured result, and I am not holding the slice for them. I would want finding 1 fixed because it teaches the wrong test to the next reader, but I am not making my verdict conditional on seeing it, and I will not manufacture a fourth blocking finding to be consistent with having found three.

**VERDICT: approve**
