From: beam_mcp · Reviewer lane r1
To: beam_mcp · Coding Agent
Re: slice 001b-ping-guard, round 3, correctness and specification conformance
Type: Report

## Tree read

```
$ cd /home/aylac/Projects/beam_mcp-wt/001b-review3 && git write-tree
7772c2a8d4bc6feefd96234c696ce4ccb9209d38
```

Matches the hash you named. Written to `001b-review3/logs-r1.tree`. `git status --short` shows
only that file and `logs-r2.tree`.

**`lib/` and `test/` byte-identical to round 2 — verified, not taken from you.** Whole-subtree
object hashes at both trees:

```
$ git ls-tree 867f28ce… lib test   /   $ git ls-tree 7772c2a8… lib test
040000 tree 13a26a2a1462a424f31fa2f7c04b208d9ad27ceb  lib     # identical at both
040000 tree a3bacd2b33321c83126ccf20fc31a6990f74a693  test    # identical at both
```

So both lanes' `lib/` conclusions still stand on bytes they read, and no re-review of the logic
is owed. This round is about the record.

**I have taken r2's lesson as the method for this round.** My round-2 check on the archives
compared counts and passed over a stripped line; every archive below is checked by `diff`
against bytes I generated myself, and where the source is remote, against my own `curl`.

---

## Finding 1 — **BLOCKING.** `logs/mutation.txt` is filtered, and is labelled as command output

`slices/001b-ping-guard/logs/mutation.txt`, asserted to be command output in two places:

- `FINDINGS.md:194`: "both mutations are now archived at `logs/mutation.txt`, **written by the
  commands that ran them**"
- `REVIEW.md:124`: "`logs/mutation.txt` added: both mutations, **written by the commands that ran
  them**"

**Observed.** I reproduced mutation A in a directory created empty and verified empty
(`0 entries`), populated by `git archive HEAD` from this index, `deps/`+`_build/` copied,
`git init`; match count asserted before and after; `mix compile --force` before scoring; and the
whole thing captured with a redirect only — no pipe, no filter. Then I diffed the bytes.

```
$ diff  raw-capture(<)  archived-block-A(>)
3d2
< Compiling 5 files (.ex)
5,8d3
< Running ExUnit with seed: N, max_cases: 64
<
< ...
<
10,17d4
<      test/beam_mcp/negotiation_test.exs:184
<      the legacy branch returns the recursion's tuple whole; if it returned the pre-recursion state instead, the transport would never stop
<      code: assert Server.shutdown?(send_for_state(legacy_meta("shutdown"))),
<      stacktrace:
<        test/beam_mcp/negotiation_test.exs:185: (test)
<
< ...........
< Finished in T

lines in raw capture:      19
lines in archived block A:  6
```

Thirteen lines removed. Corroborated across the whole file:

```
$ grep -nE 'seed:|stacktrace|Finished in|^\.+$|Compiling' logs/mutation.txt
NONE — every such line is absent from the archive
```

**Expected:** the bytes are the command's bytes. `CONVENTIONS.md:73-79` — "Either a command
reads the source and writes the file … or the file is not an archive and is not labelled one."

**Why this is blocking and not a nit.** What was stripped is not noise. The failure body —
`negotiation_test.exs:184`, the assertion message, the `code:` line, the `stacktrace:` — *is* the
evidence that this mutant was killed by that specific assertion rather than by a compile error, a
different test, or nothing at all. The archive keeps the conclusion and discards the proof, which
is the precise shape `CONVENTIONS.md:91-93` names as the worst member of the family: "an archive
reported as verbatim but never fetched is indistinguishable from evidence."

And this is the **third** occurrence in this slice and the **second** inside an artifact created
to close a finding about the first. Round 2 re-took two archives through `| tail -4` to fix a
verbatim finding; round 3 added `mutation.txt` to fix that, and filtered it. The three
run-logs that *were* in scope this round came out clean (below) — so the discipline landed on
the files under the finding and not on the new file created beside them.

**A second, smaller part of the same defect.** `logs/mutation.txt:19-22`, the
`=== scoring summary ===` block, is authored prose — "no mutation of the code under review kills
it, because nothing on the ping path touches `shutdown?`" — which no command emits. It is good
prose and I agree with every word of it (I reached it independently in round 2). It does not
belong under a label that says the file was written by commands. Put it in `FINDINGS.md`, or
give it a header in the file that says it is the author's reading of the two captures above it.

**The facts in the file are all correct — I checked them, and the defect is the form, not the
content.** Mutation A kills `:184`; mutation B kills `:191`; the third test is killed by neither.
I ran both myself, in round 2 and again now. Fixing this is a re-take, not a re-analysis.

---

## Finding 2 — non-blocking. The corrected sentence still stands, uncorrected, 97 lines earlier

`FINDINGS.md:92`:

> Round 2 added three more tests, **scored by mutation below**, for a file total of 15.

`FINDINGS.md:189-195` corrects exactly that claim — "Two of the three are mutation-killed; the
third is not, and cannot be". Both sentences are in the file, and the earlier one forward-
references "below", where the text now contradicts it.

```
$ grep -n "scored by mutation" slices/001b-ping-guard/FINDINGS.md
92:Round 2 added three more tests, scored by mutation below, for a file total of 15.
193:"scored by mutation" over a single mutant; both lanes caught it (r1 finding 1, r2 finding 4) and
```

Same class as r2's round-2 finding 2 (re-taking the evidence and leaving the quotation behind),
one round later, in the same file. Four words fix it.

---

## Finding 3 — non-blocking. The third fresh count, as you predicted. The `.md` gap is nine, not two-plus-three

You asked me to assume a third and look for it. Here it is.

`FINDINGS.md`, "Recorded in round 2, not fixed", item 6: "**two** tracked root `.md` files carry
no SPDX header … That rationale covers the **three** `logs/spec-*.md` files exactly."

Derived rather than typed, with the gate's own population command:

```
$ git ls-files -- '*.md' | while read f; do head -5 "$f" | grep -q SPDX-License-Identifier || echo "  NO-SPDX: $f"; done
  NO-SPDX: FINDINGS.md
  NO-SPDX: PLAN.md
  NO-SPDX: slices/001b-ping-guard/logs/round1.r1.md      <- added in round 3, not mentioned
  NO-SPDX: slices/001b-ping-guard/logs/round1.r2.md      <- added in round 3, not mentioned
  NO-SPDX: slices/001b-ping-guard/logs/round2.r1.md      <- added in round 3, not mentioned
  NO-SPDX: slices/001b-ping-guard/logs/round2.r2.md      <- added in round 3, not mentioned
  NO-SPDX: slices/001b-ping-guard/logs/spec-basic-versioning.md
  NO-SPDX: slices/001b-ping-guard/logs/spec-changelog.md
  NO-SPDX: slices/001b-ping-guard/logs/spec-legacy-basic.md
```

**Nine**, not two plus three. Round 3 tracked four reviewer reports, which sit in exactly the
position item 6 describes — tracked `.md`, no header, invisible to the gate — and for exactly the
reason item 6 gives: prepending an SPDX header to a lane's report would break the claim
`REVIEW.md:44-46` makes about it, that "the bytes are the reviewer's bytes, because the reviewer
wrote the file". The strongest argument in the item applies to the four files the item does not
name, in the round that added them.

r2 flagged this population itself, in the header of its own archive
(`logs/round1.r2.md:9-12`): "If `.md` is ever added to that population this file and the two spec
archives all need a decision." That count is now three spec archives and four reports.

---

## Finding 4 — note. `REVIEW.md` inflates one r1 severity by a cell

`REVIEW.md:65` records r1's finding 6.3 as **non-blocking**. My report calls it a **note**:

```
$ grep -n "^### Finding 6\.3" logs/round1.r1.md
215:### Finding 6.3 — note. `logs/probe-after.txt` predates the `mix.exs` bump
```

6.4 on the next row is recorded correctly as a note. Every other row I checked against my own
archive is right — 2.1 blocking, 4 / 1c / 2.2 / 6.1 non-blocking, 2.3 note. One cell.

---

## Finding 5 — note. `REVIEW.md:21-22` attributes to the lanes a step the lanes did not perform

> Both lanes reviewed a checkout of the **index**, not the working tree — `git archive` of
> `git write-tree`'s output into a directory created empty and verified empty.

What a lane can attest is the first half: I ran `git write-tree` in each checkout, got the hash
you named, and re-ran it at the end of round 1 to show the index had not moved. The second half —
that the directory was created empty and verified empty — describes what *you* did to build the
checkout, and neither lane witnessed it. I did create and verify-empty directories, but those
were my own mutant copies, not the review checkouts. In a file whose opening section is about not
letting a record read as a control, an unwitnessed step attributed to the reviewers is worth one
clause of rewording.

---

## Finding 6 — note. `probe-after.txt` is the one run-log no reader can reproduce

`FINDINGS.md` cites it as `$ mix run <scratchpad>/probe_ping.exs`. That script is not in the
repository:

```
$ git ls-files tools/
tools/gate.sh
$ git ls-files | grep -i probe
slices/001b-ping-guard/logs/probe-after.txt        # the output, not the program
```

So of the five run-logs, four can be regenerated by anyone with the tree and one cannot. Its
bytes are genuine and its content is correct — I verified every line of it against my own probes
in round 2, and `lib/` has not moved since. Out of round-3 scope and recorded only; if
`probe_ping.exs` were tracked, this log would join the others.

---

## Verified and closed — with bytes, not counts

**Round-3 scope item 1 — the three run-logs are clean.** Fresh raw captures in my own copy,
`> file 2>&1`, diffed against the archives with only seed and timings normalised:

```
full-suite.txt          IDENTICAL (no line stripped)
green-negotiation.txt   IDENTICAL (no line stripped)
gate.txt                BYTE-IDENTICAL (strict diff, nothing normalised)
```

The stripped `Running ExUnit with seed: N, max_cases: 64` line is back in both test logs. r2's
round-2 blocking finding is properly closed.

**Round-3 scope item 3 — all three spec archives are byte-identical to my own fetches.** This is
the check I owed from round 2, where I compared `grep -F` hits instead of bytes. I fetched each
page myself and diffed:

```
$ curl -sSL --fail .../2026-07-28/basic/versioning.md  ->  spec-basic-versioning.md   BYTE-IDENTICAL (11518 bytes)
$ curl -sSL --fail .../2026-07-28/changelog.md         ->  spec-changelog.md          BYTE-IDENTICAL (11892 bytes)
$ curl -sSL --fail .../2025-11-25/basic.md             ->  spec-legacy-basic.md       BYTE-IDENTICAL (11194 bytes)
```

They are the pages, unmodified. The new one carries the passage round 2's correction leans on, at
`spec-legacy-basic.md:73`: "The `result` **MAY** follow any JSON object structure."

**My own two reports are unaltered.** `diff` of the tracked `logs/round1.r1.md` and
`logs/round2.r1.md` against the bytes I wrote: IDENTICAL, both.

**The disclosed second `lib/` change, and its surviving mutant, are correctly reported.** I ran
that mutant myself rather than accepting the record — reverting `modernise(response, next)` to
`modernise(response, state)`, match count asserted, `mix compile --force`, then the suite:

```
before = 1 ; old_after = 0 ; new_after = 1 ; applied
15 tests, 0 failures
REAL_EXIT=0            # survives, exactly as recorded
```

A survivor that is correctly a survivor, reported as one. That is the right call and the right
disclosure.

**Round-1 count text is still correct after round 3.** Re-derived, not read: nine pre-existing
tests at `base/main`, three round-1 additions, twelve at the round-1 index, fifteen now; the
round-1 Green block's `12 tests, 0 failures` and `36 tests, 0 failures` are the round-1
measurements and their stale citations to the log files are gone, which is the right fix; the
scripted-edit table still has six data rows under "**Six** edits". The one residual is finding 2
above.

**`REVIEW.md`'s claims about the lanes check out**, apart from findings 4 and 5. Both tree hashes
at `REVIEW.md:26-27` match what each lane's archive says it read. Its quote of r1's round-1 close
is verbatim against `logs/round1.r1.md`. Its quote of r2's — "The `lib/` change is correct,
minimal, and I found nothing to fix in it" — is verbatim against `logs/round1.r2.md:195`. Its
round-2 tally, "r2: 1 blocking, 4 non-blocking", matches r2's own headers. Its statement that a
split verdict is not a pass, and that r2's blocking finding was fixed before signoff was
contemplated, is the right rule and I endorse it: **my round-2 approve was wrong on that file**,
and the reason it was wrong is that I checked numbers where the finding was about bytes.

**Gate, read per step:**

```
$ ./tools/gate.sh; echo "gate exit=$?"
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

---

## Summary

The three logs this round was scoped to fix are genuinely fixed, and I checked them the way r2
showed was necessary. All three spec archives are byte-identical to fetches I made myself. `lib/`
and `test/` have not moved. The surviving mutant is honestly disclosed and reproduces. The
substance of this slice has been right since round 1 and is still right.

One blocking item: `logs/mutation.txt` is a filtered capture presented as command output, in the
file added to close a finding about filtered captures presented as command output. Thirteen lines
per block are gone, including the failure body that is the actual evidence of the kill. The facts
it states are all true and I verified each one, so the fix is a re-take with a redirect and a
header over the prose block — not a re-analysis.

Three of the four remaining items are one-clause record fixes, and finding 3 is the third fresh
count you asked me to go looking for: the `.md` gap is nine files, not five, and the four the
item omits are the four this round added.

VERDICT: changes required
