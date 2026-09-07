<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Round 2, lane r2 — the probes, and whether they can be wrong

**Tree read:** `7ae4f8330a27316e1fa7d4927d728800575ce438` (commit `08ecf7d`), pinned in
`round2.r2.tree` and in `signoff/round2.r2.signoff`.
**Remit:** can each probe fail, and can the harness report something that did not happen.
**Verdict: CHANGES-REQUIRED.** One blocking finding.

## R2-B (blocking) — the harness scored a mutation that had never been applied

Round 2's own fix for R2-A moved the exclusion out of the line the mutant's `sed` targeted. The
substitution then matched nothing, `probe_signoff.sh` ran the **unmutated** script, and reported:

      probes as expected: 9
      probes disagreeing: 0
      mutants surviving:  2

Two survivors that do not exist. `CONVENTIONS.md` names the shape — *"a mutation reported as
applied but never applied"* — and this is the expensive direction to be wrong in: a survivor
reads as a real finding about the code, so it is acted on. A missed kill is only a gap.

It is also the same defect as everything else in this slice, one level up: the harness reported
on a mutant it had never looked at.

**Required:** every mutation goes through one helper that `cmp`s the mutant against the original
and refuses to score it when they are identical. And the refusal itself must be shown to fire —
an assertion that cannot fail is the thing this repository keeps finding.

Verified by pointing the helper at a pattern that matches nothing, changing nothing else:

      MUTATION mut1 DID NOT APPLY -- the sed matched nothing. Refusing to score it.
      S1: not scored, mutation did not apply
      S3: not scored, mutation did not apply

## Checked and found sound

- P9 is an assertion over `gate.sh`'s text rather than a plant, and it can fail: put a
  `declare -A` back on a live line and it goes red. Comment lines are stripped first, because
  the explanation beside it legitimately contains the string.
- S8's link points at an **already tracked** file, so the reviewed tree does not move and
  `STALE` cannot be what refuses. The whitelist has to be what refuses, or nothing does. That is
  the right construction for the property being tested.
- S9's scenario is a single function run against both the real tool and the mutant, so the two
  runs differ in exactly one thing.
- Round 1's records bind `9a7998d1…`, which is the tree at `6a30cb2` — the tree its lanes
  actually read. The fixes were stashed while the records were written. Re-derived here rather
  than taken from the record.
