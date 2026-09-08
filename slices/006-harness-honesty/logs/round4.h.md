<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Round 4, lane h — forced by the instrument, not by a finding

**INDEPENDENCE.** Two written passes by **one reader**, as in rounds 2 and 3.

**This round exists because `signoff.sh` refused again**, not because anything was found. After
round 3 approved, one further commit landed — untracking `signoff/verify.txt` and adding a
`.gitignore` comment — and `verify` marked both round-3 records STALE. Correctly: the tree moved
after the lanes approved it.

## What was re-read

    $ git diff <round-3 tree>..HEAD --stat
     .gitignore | 4 ++++
     slices/006-harness-honesty/signoff/verify.txt | (untracked)

One ignore rule and the removal of a regenerated file from the index. **No `lib/`, no `test/`,
no `tools/`, no archive, no verdict.** The cause was mine: a blanket `git add -A` tracked a file
`signoff.sh` rewrites on every run, which carries no SPDX header, and the widened REUSE step
failed on it exactly as it should:

    reuse FAIL (293 tracked; ...) no SPDX-License-Identifier ...
        slices/006-harness-honesty/signoff/verify.txt

A header would have been the wrong fix — the next `verify` would drop it.

## Verdict

**approve.** Nothing examined in rounds 1–3 is changed. The round-3 findings stand.

The cap being exceeded is recorded in FINDINGS as a limitation of the instrument rather than a
fourth review, together with the discipline it teaches: make every tree change first, record last.
