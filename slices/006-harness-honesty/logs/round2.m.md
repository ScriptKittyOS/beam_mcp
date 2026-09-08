<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Round 2, lane m — mechanism

**INDEPENDENCE, STATED FIRST BECAUSE IT LIMITS EVERYTHING BELOW.** This round's two lanes are
**two written passes by one reader**, not two readers. Round 1's lanes were separate agents; these
are not. A second pass by the same reader shares its assumptions, its blind spots and whatever the
first pass concluded, and "two lanes" must not be read here as independence. Recorded in the
verdict rather than in a footnote elsewhere, per the convention added in PR #14.

Tree read: `2f03bec5521bc0b45853b69667b54b2953c27eb9` (commit `716526e8aa8184a6c98abf13de931281ee1bea11`).

## What I checked

**The FIN/RST distinction, in the code rather than in the claim.** `exchange/4` at :191-236:

    {:aborted, reason, acc} when attempt < @attempts   -> repeat on a fresh connection
    {:aborted, reason, acc}                            -> raise
    {:unanswered, acc}                                 -> raise, no repeat
    {bytes, state}                                     -> measurement

A clean close carrying no answer takes the `:unanswered` branch and raises **immediately** — it
is never repeated. Only an abort is. That is the B2 fix as specified, and it is a distinction
rather than a threshold: nothing here is a tunable number deciding truth.

**The claim under it is measured, not argued.** The moduledoc at :125-163 records 250 exchanges
against the real listener: every one `:econnreset`, zero clean closes, 19 losing the response. So
"only an abort can destroy a response already written" is an observation about this adapter, with
its population and counts, not a deduction.

**Both round-1 blind spots now move**, at full-suite scale, verified by pairing label to count in
`mutation-harness-anchors-round2.txt` rather than reading them off adjacently:

    H1 -> 164 tests, 4 failures      H4 -> 164 tests, 2 failures
    H2 -> 164 tests, 1 failure       H5 -> 164 tests, 1 failure

H4 is `@attempts 5 -> 1`, deleting the repeat, which was invisible in round 1 because the
expected text interpolated `#{'#'}{@attempts}` and the mutation moved both sides together. H5 is
lane m's own round-1 attack — a server answering only on a later attempt — now a test.

## One observation, not blocking

**The de-containment rests on H4 killing, not on the stderr message.** That message still
interpolates `#{'#'}{@attempts}` (:220-224). It is the *assertion* that now carries a literal, so
the anchor moves; but a reader skimming for "the literal" will find an interpolation in the
nearest string and may conclude the fix is absent. The evidence that it is not is H4, measured.
Worth a sentence beside that message if this is touched again; not worth a round.

## Verdict

**approve.** The mechanism is right, the distinction is the correct shape, and the anchors that
prove it can move do move. `lib/` is untouched — `git diff origin/main..HEAD -- lib/` is empty.

Bounded by the independence limit at the head of this file.

## Re-read after the rebase onto PR #18

`signoff.sh verify` refused after this branch was rebased onto `main` carrying PR #18: the tree
the lanes approved (`1d9e1430`) is not the tree that now ships (`1d84c05c`). That refusal is the
mechanism working, and it is recorded here rather than worked around.

**The delta was re-read in full before re-recording**, not assumed:

    $ git diff f0350d3..HEAD --stat
     CHANGELOG.md | 4 ----
     HANDOFF.md   | 7 -------
     2 files changed, 11 deletions(-)

Eleven deleted lines in two documentation files — the stale "Known gaps" bullets that claimed the
invalid-UTF-8 defect was unfixed while the same section listed it as fixed. No code, no test, no
archive, and nothing `mix test` or `tools/mutate.sh` reads: the suite references `CHANGELOG.md`
only as a filename in `mix.exs` `files:`, never its contents.

**This verdict is unchanged by that delta**, and the re-record says so with the delta named rather
than re-approving a tree nobody looked at.
