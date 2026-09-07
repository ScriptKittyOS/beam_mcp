<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Round 1, lane r2 — the record, and the tool used on itself

**Tree read:** `9a7998d1ae1f2d8ca8b4a422b0c579c24f4aae1b` (commit `6a30cb2`), pinned in
`round1.r2.tree`.
**Remit:** does every claim in `FINDINGS.md`, in the commit messages and in the scripts'
comments match a transcript; and does the slice's own tooling survive being used on the slice.
**Verdict: CHANGES-REQUIRED.** One blocking finding, from the second half of that remit.

## R1-C (blocking) — `signoff.sh verify` can never pass on a slice that runs rounds

Found by trying to record this very round. `PLAN.md` §4's table says:

  - *any record's verdict is `changes-required`* → refuse
  - *a record's tree hash ≠ the current review tree* → `STALE`, refuse

over **every** record. Applied to a slice that actually runs rounds, those two rules make a
signoff unreachable:

  - round 1's `changes-required` record refuses forever — and needing a change is what rounds
    are **for**;
  - round 1's `approve` record goes `STALE` the instant round 2's fix commit lands, so a slice
    that runs more than one round can never be signed off either.

Measured, before the change, on this slice's own records: round 1 is `changes-required`, so
under the table as written `verify` for slice 004 could never return 0 no matter what round 3
concluded.

A check that cannot pass is the mirror of a check that cannot fail. `CONVENTIONS.md` says the
second "reads as coverage and is not"; the first reads as rigour and is not, and its only
stable outcome is to be switched off — which is how a control becomes a comment.

**Required:** the highest round decides; earlier rounds are kept and printed as history. What
must not be relaxed: every record still has to **parse**, in every round, because an
unparseable record skipped is a population member lost quietly, and that is the slice's whole
subject.

This is a departure from `PLAN.md` §4 and it is recorded as one rather than folded in silently.
The plan is left as written.

## Record claims checked against transcripts — no discrepancy found

Each of these was re-derived from the file named, not read back from `FINDINGS.md`:

| claim | source | agrees |
|---|---|---|
| baseline `reuse pass (24 commentable files)`, exit 0 | `logs/gate-baseline.txt` | yes |
| red names exactly 7 files, exit 1 | `logs/gate-red-before-coverage.txt` | yes |
| `125 − 79 − 2 = 44` and `42 + 2 = 44` | `logs/gate-after-coverage.txt` | yes |
| P1–P3 `pass` under M1 | `logs/mutation-m1.txt` | yes |
| P7 count 0, P5 count 1 under M2 | `logs/mutation-m2.txt` | yes |
| P8 `pass` under M3 | `logs/mutation-m3.txt` | yes |
| 16 verdicts / 0 tree pins in 001b | `git ls-files`, re-run | yes |
| 002 round 4: 3 pins, 1 verdict | `git ls-files`, re-run | yes |

`FINDINGS.md`'s §2a P5 disagreement is stated as a refutation of the plan rather than as a
correction to it, which is what `CONVENTIONS.md` asks for. No claim was found that a transcript
does not support.

## Not blocking, recorded

- `PLAN.md` §4 says the probe should build records "by calling `signoff.sh record`". S7 and S8
  edit a record and plant a link **after** `record` created it. That is the only way to reach
  a malformed record at all, since `record` refuses to write one, and it is the same shape as
  P8: the plant is made through the mechanism and then damaged, rather than fabricated.
- `probe_signoff.sh` uses `${id,,}`, a bash 4 construct, in its mutation loop. It is a
  developer tool rather than a gate step, and R1-A's fix does not extend to it. Recorded so the
  next reader is not surprised by an inconsistency.
