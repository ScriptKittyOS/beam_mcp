<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Slice 001b — review record

## There is no mechanical binding in this repository, and this file is not one

`tools/` holds `gate.sh`, `probe_ping.exs` and `archive_sweep.sh` — a quality gate and two
evidence instruments. **There is no `tools/signoff.sh`**, no
`Reviewed-diff` commit trailer, no index-hash check, and no hook that refuses a commit whose
diff no reviewer saw. Nothing in this repository's gates or CI reads this file.

So: this is a **record**, not a control. It is checkable by hand and it is not enforced. Stated
first and plainly, because a file named `REVIEW.md` sitting next to a `PLAN.md` in a tree whose
sibling has a real signoff mechanism will be read as a control unless it says otherwise, and a
control that does not exist is worse than a known gap.

What *is* mechanical, and is the closest thing here to a binding:

- Both lanes reviewed a checkout of the **index**, not the working tree. What a lane can
  attest is that it ran `git write-tree` in the checkout it read and got the hash below; that
  the checkout was built by `git archive` into a directory created empty and verified empty is
  the coding agent's step, which **no lane witnessed** (r1 round-3 finding 5). Separated because
  a file whose first section is about not letting a record read as a control should not attribute
  an unwitnessed step to the reviewers.
- Both lanes printed the tree hash they read, and both printed the same one, and it equalled
  `git write-tree` on the staged index:

      round 1:  a42f1b1e82599b203df0afcaaa8639203fd663d7   (r1 = r2 = index)
      round 2:  867f28cecbf790f17e7a43747c74cbc3c5990033   (index at time of dispatch)
      round 3:  7772c2a8d4bc6feefd96234c696ce4ccb9209d38   (index at time of dispatch)
      round 4:  see the commit; lib/ and test/ unchanged since 867f28ce

  Round 3's hash was missing from this list while the file described round 3 at length —
  r2 round-3 finding 4. If the list is the binding, it carries every round it binds.

- r1 re-ran `git write-tree` at the **end** of its round-1 review and got the same hash, so the
  index did not move under it mid-review. That is the failure this practice exists to prevent.

## Lanes

Two, spawned by the coding agent, read-only, adversarial, and told to report findings rather
than edit. Neither edited a file under review.

| lane | remit |
|---|---|
| r1 | correctness and specification conformance |
| r2 | security, contract, and evidence integrity |

## Round 1 — both lanes: changes required

Full reports, **written by each lane itself** into `logs/round1.r1.md` and `logs/round1.r2.md`.
They are archives in this project's sense: the bytes are the reviewer's bytes, because the
reviewer wrote the file. They were not transcribed by the coding agent, which could not have
labelled them verbatim if it had. r2's archive additionally names, in a header comment, the two
conversational lines it omitted — an omission declared rather than silent.

**Neither lane raised a finding against `lib/`'s logic.** Quoting r2's round-1 close: "The
`lib/` change is correct, minimal, and I found nothing to fix in it." And r1's: "The fix itself
is correct, minimal, well-argued against the fetched spec, and genuinely demonstrated
red-before-green by mutation. Shape (A) is the right shape and I reach that independently."

Both nonetheless returned **changes required**, on documentation and evidence:

| # | lane | severity | what |
|---|---|---|---|
| 2.1 | r1 | **blocking** | the `@moduledoc` still stated the rule the diff deletes |
| 4 | r1 | non-blocking | `shutdown` through the new legacy branch was untested; every test discarded the returned state |
| 1c | r1 | non-blocking | a changelog-item-8 inference was presented beside two quoted MUSTs as if it were a third |
| 2.2 | r1 | non-blocking | the new README claim had two reachable counterexamples |
| 2.3 | r1 | note | `modernise/2` was handed the pre-recursion state |
| 6.1 | r1 | non-blocking | three counts in FINDINGS were typed fresh and wrong |
| 6.3 / 1 | r1 note, r2 non-blocking | `probe-after.txt` measured `0.1.1`, not the tree being shipped |
| 6.4 / 6 | both | note | the PLAN's fetch date was one day in the future, and the fetch had no archive |
| 2 | r2 | non-blocking | the README asserted an envelope invariant a one-command probe falsifies on a mandatory method |
| 3 | r2 | non-blocking | a wire-visible field removal shipped under `### Fixed` with no removal label |
| 4 | r2 | note | the README's "session: yes" is tracked and never enforced |
| 5 | r2 | note | the new clause comment overstated the clause's reach |
| 7 | r2 | note | a line-number citation stale in the merged tree |
| 8, 9 | r2 | note | gate REUSE population and `-32022` echo — both out of scope |

The most useful finding is r1's 2.1, and it is worth naming why: round 1 fixed a comment that
contradicted the code, and left the **moduledoc** contradicting the code. Round 1's README
rewrite then committed the same class of error a second time (r1 2.2, r2 2) by replacing a
paragraph that overstated the rule with another paragraph that overstated it. A slice about a
comment that outlived its code reintroduced the defect twice while fixing it. That is the
argument for adversarial review stated better than any policy sentence.

## Round 2 — a split verdict, which is not a pass

Tree `867f28cecbf790f17e7a43747c74cbc3c5990033`. Full reports at `logs/round2.r1.md` and
`logs/round2.r2.md`, each written by its own lane.

    r1: VERDICT: approve                 (5 new findings, all non-blocking or note)
    r2: VERDICT: changes required        (1 blocking, 4 non-blocking)

**A split is not a pass, and was not treated as one.** r2's blocking finding stood on its own
and was fixed before any signoff was contemplated. Recording the rule because the tempting
reading of "one approve, one changes-required" is that the approve carries it, and that reading
would have shipped the exact defect r2 found.

**r2's blocking finding, and it is the sharpest in the slice.** Round 2 re-took
`logs/full-suite.txt` and `logs/green-negotiation.txt` to fix a round-1 finding that an archive
did not describe the tree it shipped with — and re-took them through `| tail -4`, which stripped
`mix test`'s first line (`Running ExUnit with seed: N, max_cases: M`). The counts were right.
The bytes were not the command's bytes. r2 proved it by `diff` against a fresh run (`1d0`) and
ruled out a configuration explanation before calling it, rather than assuming one.

So: **the fix for a verbatim-archive finding was itself a verbatim-archive violation**, in the
file offered as proof. That is the family `CONVENTIONS.md` singles out as the worst, because a
filtered archive is indistinguishable from evidence. Neither the author nor r1 caught it; r1 had
re-run both commands and compared *counts*, which is exactly the check that passes over this
defect. It took a lane that compared *bytes*.

**Both lanes independently found the same over-claim** — "three tests scored by mutation",
evidenced by one mutant — and both then ran the second mutation themselves and both concluded
the third test is unkillable in this diff's mutation space. Two lanes reaching one conclusion by
separate routes is the strongest signal either produced.

**r2 also found an undisclosed `lib/` change** by mutation rather than by reading the record:
`modernise(response, state)` -> `modernise(response, next)`, whose mutant **survives the whole
suite**. Correctly a survivor — the change is unfalsifiable today and kept as defence against a
latent trap — but round 2's record claimed every change that round was documentation, evidence
or coverage, which the tree falsified.

## Round 3 — bounded, on the delta

Scope, fixed before the lanes were dispatched and written here beside the tree:

1. `logs/full-suite.txt`, `logs/green-negotiation.txt`, `logs/gate.txt` re-taken with
   `> file 2>&1` — a redirect, no pipe, no filter.
2. `logs/mutation.txt` added. **This was itself the third instance of the archive defect** — a
   curated extract (its `mix test` piped through `grep -E`) carrying a label that claimed
   captured output. Both lanes blocked on it in round 3. Round 4 deletes it for
   `logs/mutation-a.txt` and `logs/mutation-b.txt`, each `mix test … > file 2>&1`, no pipe.
3. `logs/spec-legacy-basic.md` added — the third page, cited since round 2 and unarchived.
4. `FINDINGS.md`: the mutation sentence corrected to two-of-three; the undisclosed `lib/` change
   disclosed and its surviving mutant recorded; the Green block's stale citations removed; the
   `.md`-gap item extended to cover the three `spec-*.md` archives.
5. `CHANGELOG.md`: one clause saying `0.1.0` and `0.1.1` name the same before-state.
6. `PLAN.md`: three archived pages, not two.

**No change to `lib/` or `test/` in round 3.** Both lanes' `lib/` conclusions therefore still
stand on bytes they read.

## Round 3 — both lanes: changes required, converging on one file

    r1: VERDICT: changes required     (1 blocking, 2 non-blocking, 3 notes)
    r2: VERDICT: changes required     (1 blocking, 2 non-blocking, 1 note)

**Both lanes blocked on the same file, measured independently.** `logs/mutation.txt`, added *that
round to close the archive family*, was itself a curated extract: its `mix test` ran through
`grep -E`, and the label over it claimed captured output. r1 counted 13 lines stripped per block.

**Why that is blocking and not cosmetic**, in the lanes' framing rather than mine: what was
dropped is the failure **body** — the assertion message, the `code:` line, the `stacktrace:`
line. Those lines are the evidence that the mutant was killed *by that assertion*, rather than by
a compile error or by nothing at all. Strip them and a killed mutant is indistinguishable on the
page from a suite that failed for an unrelated reason — which is the whole thing mutation scoring
is supposed to establish.

r2 declined to soften it, and said why: an identical defect on a different file cannot be
blocking one round and a note the next, "or the standard is whatever the reviewer feels like that
morning."

**r1 retracted its own round-2 approve**, unprompted: *"I checked numbers where the finding was
about bytes."* Recorded because a lane correcting itself against the standard is the review
mechanism working, and because it is the clearest statement of the method error that let instance
#2 through — the same method error that would have let #3 through.

**Both lanes independently derived nine** headerless tracked `.md` files against a hand-written
count of five, and both observed the four omitted were the four that round added. Same population,
same number, two routes — measured rather than asserted.

## Round 4 — the population swept, not the instance fixed

The instruction that changed the approach: *a list is not a population*. Rounds 1-3 fixed one
archive per round and met the next one. Round 4 enumerates **every** file the record labels an
archive and classifies each by comparing it against a fresh capture — `logs/archive-sweep.txt` is
that sweep's own output.

The sweep is now a tracked script, `tools/archive_sweep.sh`, and **it shows every comparison it
makes** — the diff, and the seed/timing normalisation where it applies one. Its first version
printed three of its verdicts as bare `echo` lines with no diff beneath them, which r2 (round 4,
finding 3) called the shape of evidence rather than evidence: the same family again, inside the
file written to close it. It also filed the three `spec-*.md` pages under "authored prose", which
would have excused never checking the only three files whose source lives outside the tree; they
are captures, and the script now re-fetches and diffs all three against upstream.

Result, with the diff shown for each: `full-suite.txt`, `green-negotiation.txt` and `gate.txt`
raw and verified by byte diff, not by count. `mutation.txt` is deleted for `mutation-a.txt` and `mutation-b.txt`, each
`mix test … > file 2>&1` with no pipe, both mutations re-run from fresh copies with match counts
asserted and `mix compile --force` before scoring.

**`probe-after.txt` is byte-identical to a fresh run of the now-tracked `tools/probe_ping.exs`
on a warm build.** Round 4 first recorded this as "differed only by carrying *more* lines", which
is backwards — r2 round-4 finding 1. The archive has **fewer** lines than a cold-build run,
because a cold run additionally emits dependency-compile output that no run of the probe itself
produces. The direction matters more than a wording slip: **fewer lines than the run is the
signature of filtering** — it is exactly what instances #2 and #3 looked like — so it can never
be an acquittal on its own. What acquits this file is the byte-identical match against a warm
run, which is the strongest verdict any file in the slice has. The corrected reasoning is now
printed by the sweep itself rather than only asserted here. Tracking the probe closes r1's
finding 6 rather than only recording it. **Four of the five run-logs are regenerable from the
tree; `red.txt` is not, and correctly so** — it is the failing state *before* the fix, so
regenerating it would mean reverting `lib/`. Round 5 said "all five", wrong by one and in the
direction that flatters: tracking the probe moved one log across, not two. r1's round-3 report
had said four of five *and named the exception*; the record adopted the number and dropped the
exception (r1 round-5, finding 2) — the same defect as adopting r2's "four of five" without
re-deriving it. The `round*.md` files are authored by
their own lanes and the `spec-*.md` files are `curl -o` output; neither is labelled a command
capture of something it is not.

Record accuracy fixed with it: the attribution above; the severity cell; the forward-reference at
`FINDINGS.md:92` that still said "scored by mutation below" while the text below corrected it;
the `.md` population now derived by command; and `FINDINGS.md` gained the rounds-3-and-4 section
it lacked, so the file that asserts every `logs/` file is a command's bytes now records the three
rounds in which that was not true.

**No change to `lib/` or `test/` in rounds 3 or 4** — `git diff 867f28ce <round-4 tree> -- lib
test` is empty. Both lanes' `lib/` conclusions rest on bytes they read at `867f28ce`; that
sentence is the coding agent's inference from the empty diff, not a lane's attestation.

## Rounds 4, 5, 6 — and the verdict that ended them

    round 4  76452890   r1: changes required   r2: approve
    round 5  de326400   r1: changes required   r2: changes required
    round 6  d9b0c01e   r1: approve            r2: approve

Rounds 4 and 5 were spent on the **instrument** rather than the evidence: a sweep that shipped a
stale verdict, was untracked and so unre-runnable, compared four of seventeen files, filed three
fetched pages as prose so never checked them, and — in the rewrite that fixed all of that —
dropped `red.txt`, the one archive whose acquittal cannot rest on a diff at all. Round 6 added a
closing tally that exits 1 when the population and the classifications disagree, scored by
mutation rather than asserted.

Both lanes approved tree `d9b0c01e`. Committed as `a05e018`, PR #7, CI green on both checks.

## Round 7 — the version, and why it is its own round

**Owner decision, 2026-09-07: the release is `0.2.0`, not `0.1.2`.**

That touches `mix.exs` and `CHANGELOG.md`, which are **tracked**, so the tree moves away from
`d9b0c01e` — the tree both lanes actually read. A sign-off held against `d9b0c01e` does not
cover these bytes, and claiming it did would be attesting a tree nobody reviewed. Hence a
bounded round rather than an amendment.

**A correction to how that risk is usually described here.** There is no `tools/signoff.sh` in
this repository to refuse such a sign-off, re-derived rather than re-asserted:

    $ git ls-files tools/
    tools/archive_sweep.sh
    tools/gate.sh
    tools/probe_ping.exs

The opening section's load-bearing half — no signoff mechanism — holds. Its other half said
`tools/` contained `gate.sh` "and nothing else", which stopped being true in round 4 and again in
round 5 when lane findings added the other two, and round 7 re-certified it without running the
command above. That is the fresh-count family in the shape absolutes always take: written true,
never re-checked, and read as background rather than as measurement. Nothing mechanical would have stopped an amendment; the round happens because the rule is
being followed, not because a tool enforces it. Worth stating plainly, because "the tool would
have refused" is a comfortable thing to believe about a control that does not exist here.

Scope, fixed before dispatch and bounded to exactly this: `mix.exs`; the `CHANGELOG` heading,
its now-wrong patch rationale, and the `0.1.1` note; the regenerated `probe-after.txt` and
sweep, since `@server_version` is compiled from `mix.exs`; and the round-7 records. **No `lib/`,
no `test/`, and no change to the `### Changed` heading** — the owner took the semver argument
from that heading, so softening it now that the number agrees would delete the reasoning that
produced the decision.

Verdicts land in `logs/round7.r1.md` and `logs/round7.r2.md`. **If those files are absent, round
7 did not complete and the version bump is not signed off.** Read absence as absence; this file
is a record of what was reviewed, never a substitute for a verdict.

## What the coding agent did not do

It did not review its own diff, and it did not commit anything on a changes-required verdict.
