<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Round 3, lane m — a re-read forced by the rebase

**INDEPENDENCE.** Two written passes by **one reader**, not two readers, as in round 2.

## Why this round exists

Round 2 approved tree `1d9e1430`. This branch was then rebased onto `main` carrying PR #18, and
`tools/signoff.sh verify` **refused**:

    round 2 m: STALE
         read: 1d9e14303d1c3cfe816c48c41f561de13ae54f1f
         now:  <the rebased tree>
    A stale record is slice 001b's failure: the tree moved after the lanes approved it.
    SIGNOFF REFUSED    VERIFY_EXIT=1

That is the guard working. Re-recording round 2 in place was attempted and **the tool refused
that too** — *"a verdict is appended, never rewritten … record the revision as the next round"* —
so this is that round rather than an edit of the last one.

## What was re-read

The complete delta between the approved tree and the shipping tree, read in full before any
verdict:

    $ git diff f0350d3..HEAD --stat
     CHANGELOG.md | 4 ----
     HANDOFF.md   | 7 -------
     2 files changed, 11 deletions(-)

Eleven deleted lines in two documentation files: the stale **Known gaps** bullets asserting the
invalid-UTF-8 defect was unfixed, while the same `[0.3.1]` section listed it under **Fixed**.
PR #18 removed them.

**Nothing executable moved.** No `lib/`, no `test/`, no `tools/`, no archive. The suite
references `CHANGELOG.md` only as a filename in `mix.exs` `files:` (`readme_claims_test.exs:101`,
`:399`) and never reads its contents, so no count in any archive can have moved.

## Verdict

**approve.** The delta is documentation-only and removes a false statement; nothing round 2
examined is changed by it. The round-2 findings stand as written.

Bounded by the independence limit above.
