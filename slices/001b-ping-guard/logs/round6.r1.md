From: beam_mcp · Reviewer lane r1
To: beam_mcp · Coding Agent
Re: slice 001b-ping-guard, round 6, correctness and specification conformance
Type: Report

## Tree read

```
$ cd /home/aylac/Projects/beam_mcp-wt/001b-review6 && git write-tree
d9b0c01e7cd61966401b4c7d971216b073578cb9
```

Matches; `git status --short` clean. Written to `001b-review6/logs-r1.tree`.

**`lib/` and `test/` still byte-identical to `867f28ce`** — subtree hashes
`13a26a2a1462a424f31fa2f7c04b208d9ad27ceb` and `a3bacd2b33321c83126ccf20fc31a6990f74a693` at
both trees.

Everything below is measured. I ran seven attacks against the instrument in a copy created empty
and verified empty (`0 entries`), populated by `git archive` from this index, `git init` +
`git add -A` so `git ls-files` sees the same population (verified: populations diff empty). Every
mutation asserted its match count before and after.

---

## The cold-build retest you asked for, and then harder

```
$ rm -rf _build/test && ./tools/archive_sweep.sh > /tmp/sweep-cold.txt 2>&1     # exit=0
$ diff /tmp/sweep-cold.txt slices/001b-ping-guard/logs/archive-sweep.txt
  BYTE-IDENTICAL FROM A COLD BUILD — the round-5 false DIFFERS does not reproduce

$ rm -rf _build   && ./tools/archive_sweep.sh > /tmp/sweep-icecold.txt 2>&1     # exit=0
$ diff /tmp/sweep-icecold.txt slices/001b-ping-guard/logs/archive-sweep.txt
  BYTE-IDENTICAL FROM A TOTALLY COLD TREE
```

Round-5 finding 5 is closed by the exact test that found it and by a harsher one. The tracked
output now reproduces from a tree with no `_build` at all, which is more than "usually right" —
it is the header's command working on a clean checkout, which is what you claimed.

---

## Finding 1 — non-blocking. A `DIFFERS` does not fail the script; only an unclassified file does

The tally exits 1 on imbalance, so exit status is deliberately meaningful here. It is meaningful
for **completeness** and not for **correctness**. Demonstrated twice, by planting the exact
signature of instance #2 and then a subtler one:

```
ATTACK 6: strip the ExUnit banner from red.txt
  banner lines before = 1 ; after = 0
  => red.txt   DIFFERS  (a mark is missing; a filtered capture would look like this)
  EXIT=0

ATTACK 7: strip only the 'code:' lines
  'code:' lines before = 2 ; after = 0
  => red.txt   DIFFERS
  EXIT=0
```

A filtered archive — the single thing this instrument exists to detect — is reported loudly in
the verdict column and the script still exits 0. `CONVENTIONS.md:36` says "read the step's line,
not just the exit code"; `tools/gate.sh` in this same repo sets `fail=1` on any failing step and
this script does not. Today the output is read by a human and the column is loud, so this is not
live-false and I am not blocking on it. **If it is ever wired into `gate.sh` or CI it becomes
blocking**, because a filtered archive would go green. Two lines: count `DIFFERS` in `verdict()`
and fold it into the final exit.

## Finding 2 — non-blocking. The tally compares counts, not sets, and I fooled it

`tools/archive_sweep.sh:188-197` computes `ENUM` and `CLASSIFIED + AUTH` and compares the two
integers, then prints a **set** claim: "every enumerated file is classified." Two independent
slips at once cancel:

```
ATTACK 2: red.txt loses its verdict, and gate.txt is classified twice
  drop pattern before = 1 ; dup anchor before = 1
  drop remaining = 0      ; dup anchor now = 2      (both asserted applied)

  enumerated : 21
  classified : 21  (11 verdicts + 10 authored lane reports)
  => TALLY BALANCES: every enumerated file is classified.
  MUTANT_EXIT=0

  $ grep -c '=> red.txt'  -> 0        # unclassified
  $ grep -c '=> gate.txt' -> 2        # counted twice
```

The round-5 regression passes the structural fix built to catch it, and the sentence the fix
prints is false at the moment it prints it. This is latent — the shipped tally is true, all
twenty-one are distinct, and I verified that — so it is not blocking on the standard I have held
(a live false statement blocks; a latent one does not). But it is the same shape as the family:
a check whose output is a stronger claim than its computation.

The fix is small and makes the claim match the computation: have `verdict()` append its filename
to a list, and at the end `comm -23 <(git ls-files … | xargs -n1 basename | sort) <(printf '%s\n'
"${CLASSIFIED_FILES[@]}" | sort)` — then the failure message can name the file instead of
counting it.

**The tally does work against the single-slip case**, which is what it was built for. I verified
your mutation independently rather than taking it:

```
ATTACK 1 (yours): remove the red.txt verdict
  enumerated : 21 / classified : 20  => TALLY FAILS: 1 enumerated file(s) unclassified.
  MUTANT_EXIT=1

ATTACK 3 (mine): a new unclassified capture appears in logs/
  => TALLY FAILS: 1 enumerated file(s) unclassified.   EXIT=1
```

Both correct. And new lane reports are absorbed automatically, because `AUTH` globs `round*.md` —
so `round6.r*.md` will not spuriously fail it.

## Finding 3 — non-blocking. The count of counts is itself a stale hand-written count

You asked whether there is a sixth. It is the sentence that counts the previous five.

`FINDINGS.md:346`: "That is **four** fresh counts across five rounds, every one caught by a lane
and none by me."

There are five. The fifth is "all five run-logs are regenerable from the tree" — my round-5
finding 2 — and **this round corrects it** at `REVIEW.md:207` ("Round 5 said 'all five', wrong by
one"). It is not added to the running total, and it does not appear in `FINDINGS.md` at all:

```
$ grep -n "run-log\|all five" FINDINGS.md
202, 329, 341:  … all three are the "all five indented lines" fix, a different figure
                 -> the round-5 run-logs count is NOT RECORDED in FINDINGS
$ grep -n "four fresh" FINDINGS.md
346:That is four fresh counts across five rounds …
```

And the tree already contains the correct ordinal, in a file tracked three directories away:
`logs/round5.r1.md` heads that finding "**The fifth count**, and it is off by the same file". So
the record now disagrees with itself inside one commit — the total says four, the lane report says
fifth, and `REVIEW.md` corrects the fifth without incrementing the total.

The paragraph this sits in is the one arguing that "a count typed rather than derived is
indistinguishable from a derived one on the page." It is, and this is the demonstration. Also
"across five rounds" is now six.

## Finding 4 — note. The self entry names a real check and then prints a verdict nothing computed

`tools/archive_sweep.sh:179` is `verdict archive-sweep.txt 0 "(self: named check above, not an
assertion)"` — a hard-coded pass. Of the eleven `RAW` lines in the output, ten have a computation
above them and this one does not, and its parenthetical says "not an assertion" from inside the
verdict column, which is where the assertion is.

**The named check itself is genuine and I verified it**, which is the substance of round-5
finding 4:

```
printed script sha256 : de9747241aa99b48a936e79c232edbac91f18e824b94ecf025353be45b5bcb54
actual  sha256        : de9747241aa99b48a936e79c232edbac91f18e824b94ecf025353be45b5bcb54
```

The fix is a third state rather than a third check: print `SELF` (or `NAMED`) instead of `RAW`,
still counted by the tally. Then `grep '=> .*RAW'` returns only files something compared.

## Finding 5 — note. `showdiff` reports a pass over two empty inputs

```
ATTACK 4:  showdiff /tmp/empty1 /tmp/empty2
     comparison: 0 differing line(s), diff exit=0
  rc=0 -> verdict() would print RAW
```

Not reachable in this script today — `mix test` always emits output and no archive is empty, and
a one-sided empty is caught because the other side's content shows as a diff. But `showdiff` is
the helper every diff-based verdict routes through, and it has no non-emptiness guard. This is
the "reported IDENTICAL over two empty lists" defect that `CLAUDE.md` §4b records as one of the
three probe failures that motivated the run-against-a-copy rule. One line: refuse, loudly, when
either input is empty.

## Finding 6 — note. The offline path is written as tolerated and is dead-ended

```
ATTACK 5: point the three spec URLs at an unresolvable host (3 occurrences asserted, 3 replaced)
  => spec-basic-versioning.md UNCHECKED (fetch failed; offline)
  => spec-changelog.md        UNCHECKED (fetch failed; offline)
  => spec-legacy-basic.md     UNCHECKED (fetch failed; offline)
  enumerated : 21 / classified : 18  => TALLY FAILS: 3 enumerated file(s) unclassified.
  EXIT=1
```

`fetch_check` has a graceful branch that prints `UNCHECKED (fetch failed; offline)` and does not
call `verdict`, so the tally then reports a coverage gap and fails. **The direction is right** —
an unchecked file is genuinely not a classified one, and I would not want it counted. But the
UNCHECKED branch reads as a tolerated outcome and is not one, and "3 enumerated file(s)
unclassified" mis-describes "the network was down". A sentence at the tally distinguishing
*unclassified* from *unreachable* costs nothing and stops a reader diagnosing a coverage bug.

---

## Verified and closed — round 5, all five

- **Finding 1, `red.txt`.** Restored at `archive-sweep.txt:59-75` with a verdict, and with the
  reason it cannot be re-run stated rather than implied. `marks()` now **enforces** all four
  marks instead of testing two, which was r2's round-5 finding 3 — and I scored that rather than
  reading it: stripping the ExUnit banner (attacks 6) and stripping only the `code:` lines
  (attack 7) each flip the verdict to `DIFFERS`. The check has teeth.
- **Finding 2, the fifth count.** Corrected at `REVIEW.md:202-208`, accurately, with the right
  diagnosis — four are regenerable, `red.txt` is not and correctly so. See finding 3 for the
  knock-on.
- **Finding 3, empty diff vs diff that never ran.** Every diff-based verdict is now preceded by
  `comparison: 0 differing line(s), diff exit=0`. A check that did not execute can no longer
  render as a pass. The pass-notes were also reworded to describe what is printed rather than an
  absence, and the two-note `verdict()` fixes the "DIFFERS (empty diff above = identical)"
  contradiction r2 found.
- **Finding 4, the self section.** Now names its check — script `sha256` plus the one-line
  reproduce command — and the hash matches. Substantively closed; see finding 4 for the column.
- **Finding 5, build warmth.** Closed, verified cold and ice-cold, above. `norm()` absorbs the
  compile prologue with the reason at the point of use, and the explicit warm-up removes the
  undocumented load-bearing ordering r2 found.

**Gate:** six `pass` lines, `19 commentable files`, `gate exit=0`.
**`logs/round5.r1.md`** as tracked is byte-identical to the bytes I wrote.
**The sweep's own claim about round 5** — "19 listed, 18 classified" — matches what I measured
that round.

---

## Summary

This is the first round where I find nothing blocking, and I want to be explicit about why I
trust that, given that my round-2 approve was wrong. Round 2 I compared counts. This round I
byte-diffed the instrument's entire output against fresh runs from a cold and an ice-cold tree,
reproduced your tally mutation independently, and ran six more attacks of my own against
`showdiff`, `marks()`, the tally and the offline path. The instrument survived four of the seven
and the three it did not survive are latent, not live: the shipped output's eleven verdicts are
each correct, the tally is truthful, and no archive in the tree is filtered.

What remains is one behavioural gap I would fix before this script goes anywhere near CI — a
`DIFFERS` does not affect the exit status — one latent false-pass in the tally's count-not-set
comparison, one in `showdiff` over empty inputs, and the sixth-order count: `FINDINGS.md:346`
says four where the tree's own `logs/round5.r1.md` says fifth and `REVIEW.md:207` corrects the
fifth without incrementing the total.

If r2 weighs the exit-code gap as blocking I would not argue against it; consistency between the
lanes is worth more than my ordinal, and the argument for blocking it is one wiring decision
away from being right.

VERDICT: approve
