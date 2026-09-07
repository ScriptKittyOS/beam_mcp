<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Slice 004 — findings

The subject of the slice, from `PLAN.md`: **a check that reports on a population it did not
derive is not a weaker check, it is a false one** — it prints `pass` over the thing it never
looked at. Everything below is an instance.

---

## The review closing rule, stated before round 1 opens

Written here first, and deliberately, because a closing rule invented after the rounds is a
rule chosen to fit the result.

- **Three rounds maximum.** Two independent lanes per round.
- **Every round writes both artefacts for every lane, at the round's close, not at the end of
  the run:** `logs/round<N>.<lane>.md` (the verdict) and `logs/round<N>.<lane>.tree` (the tree
  pin the lane read). `CONVENTIONS.md`: *"A report owed only at the end is a report a crash
  deletes."* A round of this slice without a tree pin would also be self-refuting, since
  `tools/signoff.sh` is the slice's own answer to unpinned verdicts.
- **The slice closes when a round returns two `approve` verdicts against the same tree hash,
  or when round 3 closes — whichever comes first.**
- **If round 3 closes with anything outstanding, the outstanding item is written into
  "Open, recorded rather than fixed" below and the PR is opened saying so.** It is not carried
  into a fourth round and it is not quietly dropped.
- **No commit is made on a `changes-required` verdict.** A finding is fixed, or it is recorded
  as open with the argument for why it is being left.

---

## Task 1 — the REUSE population and the `licence files` verdict (SCR-262)

### The red, measured before anything was changed

    $ ./tools/gate.sh                            # logs/gate-red-before-coverage.txt
      reuse                      FAIL (123 tracked; 42 in scope, 35 headered + 0 sidecar; excluded 79 archive + 2 licence text)
          no SPDX-License-Identifier in the file or in a <path>.license sidecar:
            .gitignore
            FINDINGS.md
            HANDOFF.md
            NOTICE
            PLAN.md
            mix.lock
            slices/002-streamable-http/FINDINGS.md
      licence files              pass
    GATE_EXIT=1

On `main` the same step reads `reuse pass (24 commentable files)` and the gate exits 0
(`logs/gate-baseline.txt`). **122 tracked files, 24 looked at, `pass` printed over the other 98.**

### The green, at the tree that ships

    $ ./tools/gate.sh                            # logs/gate-after-coverage.txt
      format                     pass
      compile                    pass
      test                       pass
      credo                      pass
      optional deps              pass
      docs                       pass
      reuse                      pass (125 tracked; 44 in scope, 42 headered + 2 sidecar; excluded 79 archive + 2 licence text)
      licence files              pass
    Gate OK.
    GATE_EXIT=0

The counts reconcile: `125 − 79 archive − 2 licence text = 44 in scope`, and
`42 headered + 2 sidecar = 44`. The 42 is the previous 35 plus the five new headers plus the
two sidecar files, which are themselves tracked and carry the identifier in their own heads.

### Seven files, not the nine `PLAN.md` §2a predicted

`PLAN.md` §2a names nine and prescribes four `.license` sidecars, including `LICENSE` and
`LICENSES/Apache-2.0.txt`. The shipped `gate.sh` recognises a licence text by **content hash**
against `LICENSES/*`, so both are covered without a sidecar and without either path appearing
in the script as a name. The step says so on every run: `excluded 2 licence text`. Recorded
here rather than by editing §2a.

### Three defects fixed in `tools/gate.sh`, and only two were in the plan

| # | defect | anchor | mutation that kills the anchor |
|---|---|---|---|
| 1 | population was `git ls-files -- '*.ex' '*.exs' '*.sh' '*.yml'` under a comment reading *"never from a hand list"* | P1, P2, P3 | **M1** — revert the population to the glob; all three return to `pass` |
| 2 | sidecar looked up with `[ -f "$f.license" ]`, a **filesystem** test beside a `git ls-files` population | P8 | **M3** — revert to `[ -f ]`; P8 returns to `pass` |
| 3 | `licence files` verdict guarded by the **shared** `$fail` accumulator | P7 | **M2** — revert to `[ "$fail" -eq 0 ]`; P7's line count goes to 0 |

**Defect 2 was found during this slice, not planned.** It is `CONVENTIONS.md` instance #1
— *"an unadded file is invisible to `git ls-files`"* — reappearing on the **coverage** side of
the same check the convention was written about. Measured red (`logs/red-sidecar-untracked.txt`):
a tracked `probe-sidecar.yaml` with an **untracked** `probe-sidecar.yaml.license` gave

      reuse                      pass (126 tracked; 45 in scope, 42 headered + 3 sidecar; ...)
    GATE_EXIT=0

counting a sidecar that does not exist in a fresh clone or in CI. After the fix the same plant
reads `FAIL`, and `git add`ing the sidecar — nothing else changed — returns it to `pass`. The
anchor moves in both directions.

### `PLAN.md` §2a's P5 row is falsified by measurement

This is the disagreement the run found, and it is recorded rather than reconciled.

§2a predicts that before the fix, P5 (missing `NOTICE` **plus** an earlier step red) shows the
`licence files` line **absent**. It does not. `logs/probe-gate-honesty-before.txt`, captured
against the unfixed script:

      -- P5: unheadered probe-gate-honesty.sh (reuse red under BOTH populations) + NOTICE renamed away
         reuse line        :  reuse                      FAIL -- no SPDX-License-Identifier:
         licence files line:  licence files              FAIL -- NOTICE missing
         licence files line count: 1   (0 means the step printed NOTHING)

Reading the old code says why — only the **pass** branch was ever guarded:

    for f in LICENSE NOTICE LICENSES/Apache-2.0.txt; do
      [ -f "$f" ] || { note "licence files" "FAIL -- $f missing"; fail=1; }   # unguarded
    done
    [ "$fail" -eq 0 ] && note "licence files" "pass"                          # guarded

P5 renames `NOTICE` away and thereby forces the one branch that always printed. It measures
**identical before and after** and anchors nothing. The input that vanishes the line is the
opposite of P5's: an earlier step red with **every licence file present**.

That is P7, added against the plan rather than from it, and mutant M2 confirms it discriminates:

    M2 (shared accumulator restored), logs/mutation-m2.txt
      P5  licence files line count: 1     <- unchanged, as the false prediction's own probe
      P7  licence files line count: 0     <- the line vanishes
      P1  licence files line count: 0
      P2  licence files line count: 0
      P3  licence files line count: 0
      P8  licence files line count: 0

M2 also shows the defect's real reach: **any** red reuse step deleted the line, not only the
one P5 constructs. P5 is kept in the harness, with the refutation appended beside it, as the
record of a prediction the run overturned.

### Probe results — every row measured, none typed fresh

`tools/probe_gate_honesty.sh`, one committed re-runnable harness. It refuses on a dirty tracked
tree, plants through `git add` (an unadded plant is invisible to the population and would be
scored as a `pass` the check was right to give), runs the **real** `./tools/gate.sh`, reads the
**step line** rather than the exit code, and asserts `git status --porcelain` clean afterwards.

before = `logs/probe-gate-honesty-before.txt` (unfixed script);
after = `logs/probe-gate-honesty-after.txt` (tree `34c27e0`).

| probe | plants | before | after | expected? |
|---|---|---|---|---|
| P0 | unheadered `.yaml`, **not** `git add`ed | `reuse pass` | `reuse pass` | yes — the control. The probe is at fault, not the check |
| P1 | unheadered `.yaml`, added | `reuse pass` | `reuse FAIL`, names it | yes |
| P2 | unheadered extensionless `PROBEGATEHONESTY`, added | `reuse pass` | `reuse FAIL`, names it | yes |
| P3 | unheadered `.md`, added | `reuse pass` | `reuse FAIL`, names it | yes |
| P4 | unheadered `.yaml` + **tracked** sidecar | `reuse pass` | `reuse pass` | yes — the sidecar covers, and it is the covering mechanism rather than an exception to the population |
| P5 | unheadered `.sh` + `NOTICE` renamed away | `licence files` **count 1**, `FAIL` | count 1, `FAIL` | **NO — §2a predicted count 0. See above.** |
| P6 | `LICENSE` renamed away, nothing else | `licence files FAIL` | `licence files FAIL` | yes — unchanged, and recorded as not-new-coverage |
| P7 | unheadered `.sh`, all licence files present | count **0** (M2) | count 1, `pass` | yes — 2b's only real anchor |
| P8 | unheadered `.yaml` + **untracked** sidecar | `reuse pass` (M3) | `reuse FAIL`, names it | yes |

P7's and P8's "before" columns are read from mutants M2 and M3 rather than from the unfixed
script, and that is the stronger comparison, not a weaker one: each mutant changes **one line**,
so the probe's swing is attributable to that line. Both mutant diffs are printed at the head of
their own transcript.

### Mutations — all three, and each is one line

`PLAN.md` §2a prescribes M1. M2 and M3 were added because defects 2 and 3 would otherwise have
no mutation at all.

| mutant | the one line changed | prediction | measured |
|---|---|---|---|
| M1 | `done < <(git ls-files)` -> the four-extension glob | P1, P2, P3 return to `pass` | **P1, P2, P3, P8 all `pass`, GATE_EXIT=0.** P5 and P7 stay `FAIL` — their plant is a `.sh`, in both populations by design |
| M2 | `[ "$lic_fail" -eq 0 ]` -> `[ "$fail" -eq 0 ]` | P7 line count -> 0 | **P7, P1, P2, P3, P8 -> 0. P5 -> 1** |
| M3 | `[ -n "${tracked[$f.license]-}" ]` -> `[ -f "$f.license" ]` | P8 returns to `pass` | **P8 `pass`, GATE_EXIT=0; every other probe unchanged** |

Transcripts: `logs/mutation-m1.txt`, `logs/mutation-m2.txt`, `logs/mutation-m3.txt`. Each was
produced on a throwaway branch with the mutant committed, because the harness refuses to run on
a dirty tracked tree — so the mutation is a real tree the probe read, not an edit made
underneath it.

One detail worth reading in M1: the counts collapse to `26 tracked; 26 in scope, 0 archive +
0 licence text`. Under the glob there is nothing to exclude, because there was nothing in scope
to exclude *from*. The exclusion counts the fixed step prints are only meaningful because the
population is the whole tree.

---

## Open, recorded rather than fixed

- **`slices/*/logs/` is outside the REUSE step.** Source code placed there escapes it. The
  exclusion is counted and printed on every run so it cannot grow quietly, but the limit is
  real. Stated in `gate.sh` itself rather than only here.
- **`archive_sweep.sh` exits non-zero on `main`** after the SCR-263 fix at `3eddb8a`, because
  three of slice 001b's archives have drifted from a tree that has since moved. That is drift,
  named rather than silenced. Re-capturing those archives is slice 001b's record to change, not
  this slice's, and the script is therefore **not** wired into `gate.sh` or CI.
- **`HANDOFF.md` was touched by this slice for its SPDX header only** — five inserted lines,
  zero deleted, verified by `git diff --cached --stat`. Its *content* belongs to the concurrent
  `slice/003-release-0-3-1`, which is fixing it. The merge-time overlap is that branch owner's
  to resolve; the coordinator has been told.
- **`PLAN.md` §5 prescribes six commits; this slice made fewer**, collapsing "derive the
  population" and "the licence verdict is its own" into one `tools/gate.sh` commit. The reason
  §5 gives for the ordering — *"so no commit leaves the gate red"* — is satisfied: the coverage
  commit lands first and the gate is green at every commit on the branch. Recorded because the
  divergence is from the plan, not from the reason.
