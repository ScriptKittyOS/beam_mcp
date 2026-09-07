<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Round 3, lane r1 — mechanism

**Tree read:** `38e1d07c688d3af174a0ee1dd704b6c9367044bb`, the review tree at commit `12345d6`,
pinned in `round3.r1.tree`.
**Verdict: APPROVE.** Nothing blocking.

## Round 1 and round 2 fixes re-checked, not taken on trust

| finding | how it was re-checked at this tree | result |
|---|---|---|
| R1-A bash 3.2 | P9, which greps live lines of `gate.sh` for bash-4-only constructs | `pass`, and the construct is gone rather than guarded |
| R1-B symlink | S8, whose link points at an already tracked file so `STALE` cannot be what refuses | refused by name |
| R1-C round semantics | S9, plus mutation 2 restoring `PLAN.md` §4's literal table | S9 passes; the mutant breaks it |
| R2-A `grep -z` | no `grep` remains in `review_tree`; the exclusion is a shell glob and `git rm -r --cached` | S1 and S3 pass; mutation 1 breaks both |
| R2-B unapplied mutation | `mutate` `cmp`s every mutant against the original | both mutations report their diff; the refusal was shown to fire |

## The runs, at this tree

    $ ./tools/gate.sh                      GATE_EXIT=0, every step line `pass`
    $ ./tools/probe_gate_honesty.sh        P0-P9 all as expected, EXIT=0
    $ ./tools/probe_signoff.sh             9 as expected, 0 disagreeing, 0 mutants surviving, EXIT=0

`logs/gate-round3.txt`, `logs/probe-gate-honesty-round3.txt`, `logs/probe-signoff.txt`.

## Recorded, not blocking

- `signoff.sh`'s `record` cannot bind a commit other than `HEAD`, so the review-record-fix
  ordering is enforced by the operator rather than the tool. Both earlier rounds got it wrong
  and both were recovered by hand. Designing the fix now, after two hand recoveries and with no
  round left to review it, would be worse than recording it. In "Open".
- `echo "note: $note"` in `record` would be a `printf` in a stricter script. Bash's `echo`
  does not interpret backslashes without `-e`, so nothing is wrong today.
