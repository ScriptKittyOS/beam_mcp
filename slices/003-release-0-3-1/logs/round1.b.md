# Round 1, lane b — the shipped artefact, and the record

Tree read: `1d27f1a0cd3265f45cd7ef0ca64ea10f584f6e2a` (commit `b821818`). Pin: `round1.b.tree`.
Scope: the two commit messages on this branch, every log they cite, `README.md`, `CHANGELOG.md`,
`mix.exs`, `HANDOFF.md`. Method: every population claim re-derived by running the command the
record says produced it, rather than reading the claim.

**Verdict: changes required (two), and they are made.**

## Blocking

**B1. The site count is wrong, in three places, and in the direction that hides a site.** The
(d) commit message, `before_body/2`'s comment and `http_bandit_test.exs`'s comment all say

> SIX refusal sites sit at or before the read -- the Origin 403, the 405, `authorize/1`'s 500,
> its 403 and its contract-violation 403, and `read_body_bounded/1`'s own 400 -- and only the
> 413 called `close_after/1` for itself.

The sentence names six and then names a seventh. Re-derived:

    $ grep -n '{:refused,' lib/beam_mcp/transport/http.ex     -> 14 hits

of which three are not sites (the comment quoting itself, `handle/2`'s `else`, and
`before_body/2`'s own close), four are on the far side of the body read (three in `decode/2`,
one in `check_headers/3`), and **seven** are at or before it: the Origin 403, the 405,
`authorize/1`'s 500 / 403 / contract-violation 403, and `read_body_bounded/1`'s **413 and 400**.
One of the seven already closed. Six did not.

The fix ships the right behaviour -- all seven go out through one path -- so this is a record
defect, not a code defect. It is blocking anyway: an off-by-one in the population is the exact
shape of the defect the commit claims to have fixed, and a reader checking the work against the
sentence would conclude the 413 was outside the set.

**Fixed** in `before_body/2`'s comment, in `read_body_bounded/1`'s comment and in the test file.
The (d) commit message is not rewritten -- corrections are appended, never rewritten -- so the
correction is recorded in `FINDINGS.md` and carried by the code.

**B2. The derivation command no longer finds the thing it was published to find.** The record
quotes

    $ grep -n '<- check_origin\|<- check_method\|<- authorize\|<- read_body_bounded' \
        lib/beam_mcp/transport/http.ex

as the command that shows where the body read sits among the steps. Run on the shipping tree it
returns the three checks and **not** `read_body_bounded`, because the fix moved that call out of
the `with` clause list and into the `with` body, where there is no `<-`. A derivation that
cannot see the boundary it defines is not a derivation, and this one was true only of the tree
it was written against.

**Fixed**: the published derivation is now

    $ grep -n 'defp before_body' -A 10 lib/beam_mcp/transport/http.ex
    $ grep -n '{:refused,' lib/beam_mcp/transport/http.ex

The first shows the steps *and* the read; the second lists the sites to place against them.
Re-run on the shipping tree, the first returns the function body including
`read_body_bounded(conn)`. Both greps also match the comment that quotes them, and the comment
now says so -- the same self-match slice 002 recorded and this comment reproduced.

## Read and accepted

- **No tool-attribution trailers, no board identifiers.** Derived:
  `git log c54046a..HEAD --format='%H%n%B' | grep -niE 'co-authored|claude|generated with|SCR-[0-9]+'`
  returns no hits. `c54046a`, which carries `(SCR-275)`, is inherited from before this work and
  was not propagated.
- **Both commits carry `Signed-off-by: Ayla Croft <aylacroft@proton.me>`**, from
  `git log --format='%h %(trailers:key=Signed-off-by,valueonly)'`.
- **Every count quoted in a commit message is the count in the log it cites.** Checked
  mechanically against the nine cited logs; all nine match on both the test line and
  `TEST_EXIT`. Two totals differ between the commits (147 and 156) and that is the tree growing,
  not a re-labelled run -- the failure slice 002 round 7 recorded.
- **The archives are whole.** Each was written by `{ cmd; echo EXIT=$?; } 2>&1 | tee <log>`, so
  the file holds the run's own bytes including its stderr and its exit code. Nothing was piped
  through `grep` into a log; where output was filtered for reading, the filter ran on `tee`'s
  stdout and not on the file.

## Filed, not blocking

**B3. `README.md`, `CHANGELOG.md`, `mix.exs` and `HANDOFF.md` are all still at `0.3.0` and
describe none of this slice's behaviour.** Expected at this point -- the plan puts them in one
release commit, which is deliberate because that is the commit that makes their statements true
-- and named here so that if this round were the last thing that happened, the next reader knows
they are outstanding rather than overlooked. `HANDOFF.md` additionally still says
`Version 0.3.0, unreleased` and names branch head `bdb032f`, both stale on `main` before this
slice began.
