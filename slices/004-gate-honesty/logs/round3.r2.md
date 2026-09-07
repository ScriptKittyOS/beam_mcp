<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Round 3, lane r2 — the record

**Tree read:** `38e1d07c688d3af174a0ee1dd704b6c9367044bb`, the review tree at commit `12345d6`,
pinned in `round3.r2.tree`.
**Verdict: APPROVE.** Nothing blocking.

## Every claim in FINDINGS re-derived from the file it cites

Re-derived, not read back. Each row was checked against the named transcript or by re-running
the command.

| claim | source | agrees |
|---|---|---|
| baseline `reuse pass (24 commentable files)`, exit 0 | `logs/gate-baseline.txt` | yes |
| the red names exactly 7 files, exit 1 | `logs/gate-red-before-coverage.txt` | yes |
| `160 − 105 − 2 = 53` and `51 + 2 = 53` at the shipped tree | `logs/gate-round3.txt` | yes |
| P1–P3 return to `pass` under M1 | `logs/mutation-m1.txt` | yes |
| P7 count 0 and P5 count 1 under M2 | `logs/mutation-m2.txt` | yes |
| P8 `pass` under M3 | `logs/mutation-m3.txt` | yes |
| the bash 3.2 run says `pass (10 tracked…)` and `EXIT=0` | `logs/round1-bash32-simulation.txt` | yes |
| the unheadered signoff records turned `reuse` red | `logs/red-signoff-records-unheadered.txt` | yes |
| 16 verdicts / 0 tree pins in 001b; 3 pins / 1 verdict in 002 round 4 | `git ls-files`, re-run | yes |
| round 1 records bind `9a7998d1…`, round 2 `7ae4f833…` | the record files | yes |

## The disagreements are recorded as disagreements

`PLAN.md` §2a's P5 row and §4's `verify` table are both contradicted by measurement. Both are
left standing in the plan with the refutation recorded beside them, which is what
`CONVENTIONS.md` asks for — corrections are appended, never rewritten. Nothing in `PLAN.md` was
edited to match a result.

## The one thing this record cannot claim

Both lanes are the same agent. It is stated at the top of "Open" rather than buried, and it is
the reason the round table should be read as one reviewer working twice rather than as
independent agreement.

## Recorded, not blocking

- `logs/round3.*.tree` names `38e1d07c…` while `signoff/round3.*.signoff` binds the shipped
  tree, and the two differ by exactly the commit that adds this record. A tree pin cannot live
  inside the tree it pins. That is the structural argument for the signoff directory's
  exclusion, and it is in "Open" as a property rather than a defect.
- `PLAN.md` §3's four `mix docs` honesty questions were not investigated. The plan marks them
  time-boxed and optional; the rounds went elsewhere. No claim is made about that step.
