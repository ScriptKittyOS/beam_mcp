From: beam_mcp · Reviewer lane r1
To: beam_mcp · Coding Agent
Re: slice 001b-ping-guard, round 7, correctness and specification conformance
Type: Report

## Tree read

```
$ cd /home/aylac/Projects/beam_mcp-wt/001b-review7 && git write-tree
d96ee6c11b1fff791a61b3eab4c17cd91ae35901
```

Matches; `git status --short` clean. Written to `001b-review7/logs-r1.tree`.

**`lib/` and `test/` untouched — confirmed two ways.** `git diff a05e018 d96ee6c1 -- lib test` is
empty, and the subtree object hashes are still `13a26a2a1462a424f31fa2f7c04b208d9ad27ceb` (lib)
and `a3bacd2b33321c83126ccf20fc31a6990f74a693` (test) — the same objects as `867f28ce`, the tree
both lanes' `lib/` conclusions rest on. Those conclusions still stand on bytes we read.

The delta is exactly the declared scope: `mix.exs`, `CHANGELOG.md`, three run-logs, and appended
records in `PLAN.md`, `FINDINGS.md`, `REVIEW.md`. Nothing else moved.

---

## Finding 1 — **BLOCKING.** `README.md:16` still tells users to depend on `~> 0.1`

```elixir
def deps do
  [{:beam_mcp, "~> 0.1"}]
end
```

This is the one you asked me to look for — a live artifact that is now wrong — and it survived
your sweep because **the stale string is not `0.1.2`**. A grep for the number that changed cannot
find a version reference written as `0.1`, and that is the whole reason to look for the class
rather than the string.

**Measured, not recalled.** I did not want to assert Hex requirement semantics from memory, so I
ran Elixir's own `Version` module in the review copy:

```
  ~> 0.1     0.1.0=true   0.1.2=true   0.2.0=true   1.0.0=false
  ~> 0.1.0   0.1.0=true   0.1.2=true   0.2.0=false  1.0.0=false
  ~> 0.2     0.1.0=false  0.1.2=false  0.2.0=true   1.0.0=false
```

So I want to be precise about what is and is not wrong here, because overstating it would be
worse than missing it: **`~> 0.1` resolves to `0.2.0`. Nothing is broken.** A new user copying
the snippet today installs the right version.

The defect is the other direction, and it is exactly the thing this release exists to signal.
A consumer who copied that snippet at `0.1.0` and runs `mix deps.update beam_mcp` is carried to
`0.2.0` **with no change to their own requirement and no signal of any kind** — across the break
the `CHANGELOG` opens by telling them to read before upgrading:

> **Read this before upgrading if any client sends `_meta` naming `2025-11-25`.** A result
> answering such a request no longer carries `resultType` or `_meta`
> `io.modelcontextprotocol/serverInfo`.

The owner chose a minor bump precisely so that a consumer *can* depend on the old behaviour. The
README hands them a requirement under which they cannot: `~> 0.1` spans both sides of the break,
`~> 0.2` does not. Publishing `0.2.0` with a README recommending `~> 0.1` ships the version
signal and the advice that defeats it in the same release.

**Why I am blocking on it rather than noting it**, on the standard I have held since round 1:
this is shipped, user-facing documentation that is stale about the change under review. `mix.exs`
puts `README.md` in the Hex package `files:` list and makes it the ex_doc landing page
(`docs: [main: "readme"]`), so after `mix.exs` it is the most-read live artifact in the tree. My
round-1 blocking finding was a moduledoc that described the pre-change behaviour after the
change; this is the same class one file over, and the round's own acceptance question was whether
any live artifact had been left behind. The fix is one character.

Two things I checked so as not to overstate it: `git grep '~>'` finds no other self-referential
pin, and `mix.exs` derives `@server_version` from `@version` rather than restating it, so no
other live file carries a hard-coded version.

---

## Finding 2 — non-blocking. "Only the live artifacts move" names the wrong set, in both directions

`FINDINGS.md:434-437`:

> Only the *live* artifacts move: `mix.exs`, the `CHANGELOG` entry, and the regenerated
> `probe-after.txt`, whose `serverInfo` is read from `mix.exs` at compile time.

Measured against the delta:

```
$ git diff --stat a05e018 d96ee6c1 -- slices/001b-ping-guard/logs/
 full-suite.txt        | 4 ++--     <- moved, not named
 green-negotiation.txt | 4 ++--     <- moved, not named
 probe-after.txt       | 4 ++--     <- named
```

`full-suite.txt` and `green-negotiation.txt` also moved — new seed, new timing — and neither
contains a version string, so the stated reason ("`serverInfo` is read from `mix.exs`") does not
explain them. And in the other direction, `README.md:16` is a live artifact that did not move and
should have (finding 1). The sentence is a list, and both the omission and the inclusion matter
because the paragraph's job is to justify which files were touched.

I am not saying re-taking the other two was wrong. Re-taking every run-log when the tree moves is
the correct discipline and is the fix for instance #1 — an archive of a tree that was not being
shipped. It just is not what the record says was done, or why.

**Related, same paragraph family:** `PLAN.md:222-223` and `REVIEW.md` both give the scope as "the
regenerated `probe-after.txt` **and sweep**". `archive-sweep.txt` is not in the delta. That is the
right outcome and I verified it rather than assuming — re-running the sweep produces byte-identical
bytes because its output carries no version string — so "regenerated" is defensible; but listing
it among the things that changed, while the two logs that did change go unnamed, gets the scope
backwards in both entries.

## Finding 3 — non-blocking. The sentence under the grep does not describe the grep's output

`FINDINGS.md:429-433` prints a command and then says what it returns:

```
    $ grep -rn '0\.1\.2' --include='*.md' . | grep -v _build | grep -v deps/

still returns hits in `logs/round*.md` and in this file's own record of rounds 1-6.
```

I ran it:

```
      8 slices/001b-ping-guard/PLAN.md          <- the largest group, not named
      7 slices/001b-ping-guard/logs/round1.r2.md
      7 slices/001b-ping-guard/FINDINGS.md
      1 slices/001b-ping-guard/REVIEW.md        <- not named
      1 slices/001b-ping-guard/logs/round4.r2.md
      1 slices/001b-ping-guard/logs/round2.r2.md
      1 slices/001b-ping-guard/logs/round2.r1.md
      1 slices/001b-ping-guard/logs/round1.r1.md
```

`PLAN.md` has more hits than any other file and is not in the description; `REVIEW.md` is not
either. Both are legitimate — `PLAN.md`'s eight include the superseded `## Version` section, which
is correctly left as written — so this is a description that under-reports its own output, not a
sweep that missed something. It matters only because the sentence exists to account for every
remaining hit, and it accounts for six of eight files.

---

## The two deliberate non-changes — checked, not assumed

**The `### Changed` heading reads correctly under a number that now agrees with it, and does not
read as a leftover.** I looked for the failure mode you named and it is closed by the paragraph
directly beneath the heading, which was rewritten:

> The argument for a patch was available and is rejected: `0.y.z` sits outside semver's
> compatibility contract, and the removed fields were never correct … Neither of those makes the
> wire change smaller. … The minor bump is the honest signal, and the `### Changed` heading above
> stays exactly as it was written when the number still disagreed with it.

That last clause is what makes the non-change legible: a reader is told the heading predates the
decision and why it stands. The old text argued *for* a patch and would have been flatly wrong at
`0.2.0`; it is inverted, not softened, and `**That is why this is 0.2.0 and not a patch.**` now
sits where the patch rationale used to. The heading is load-bearing, and I agree with keeping it.

**No archive was wrongly swept.** All six of my reports as tracked are byte-identical to the bytes
I wrote:

```
round1.r1.md … round6.r1.md:  IDENTICAL to the bytes I wrote  (6/6)
```

The twelve lane reports and the historical tables keep their `0.1.2` strings, which is right —
I did measure `beam_mcp version: 0.1.2` in round 2, and an archive that is edited to match a later
tree is not an archive. `PLAN.md`'s `## Version` section is superseded by an appended note
immediately below it rather than rewritten, which is the same rule applied correctly.

---

## Verified

- **`mix.exs`** reads `0.2.0`; `@server_version` is still derived from it, not restated.
- **`probe-after.txt`** reads `beam_mcp version: 0.2.0` and its modern `serverInfo` carries
  `"version":"0.2.0"` — both occurrences, not just the banner.
- **The sweep reproduces byte-identically from a tree with no `_build` at all**, in a copy created
  empty and verified empty (`0 entries`), `git archive` from this index, `git init` + `git add -A`
  so the population matches (verified: populations diff empty):

      sweep exit=0 ; diff vs tracked archive-sweep.txt -> BYTE-IDENTICAL
      enumerated : 23 / classified : 23  (11 verdicts + 12 authored lane reports)
      => TALLY BALANCES ; zero DIFFERS anywhere in the file

  That is not just a tally check: the sweep diffs `full-suite`, `green-negotiation` and
  `probe-after` against fresh runs, so its clean result independently proves all three re-taken
  logs match commands run at `0.2.0`. If one had been left at `0.1.2` it would have gone `DIFFERS`.
- **`CHANGELOG` `0.1.1` note** now states the jump in terms — the number was taken on `main`, the
  release never happened, the moduledoc fix ships inside `0.2.0`, and the section is kept under its
  original heading. A reader comparing Hex to the file no longer has to reconstruct it.
- **No `tools/signoff.sh`.** `git ls-files tools/` returns `archive_sweep.sh`, `gate.sh`,
  `probe_ping.exs`. Your `REVIEW.md` correction is accurate: nothing mechanical would have refused
  an amendment, and saying so beats implying a control that does not exist. I would rather read
  that sentence than the comfortable one.
- **My round-6 finding 3** (the count of counts) was closed better than I proposed: the tally is
  **deleted rather than corrected**, on the reasoning that a freshly typed "five across six" would
  repeat the defect while fixing it, and no command in the tree derives the number. The instances
  stay enumerated in the table where a reader can count them. That is the right answer and it is
  not the one I suggested.
- **Gate:** six `pass` lines, `19 commentable files`, `gate exit=0`.

---

## Summary

The version change itself is correct and the round is properly bounded: `lib/` and `test/` are
byte-identical to the tree both lanes approved, the delta is exactly the declared scope, the three
re-taken logs are proved to match fresh runs at `0.2.0` by a sweep that reproduces byte-for-byte
from a cold tree, and no archive was falsified to make the tree look tidy. The `### Changed`
heading survives as load-bearing rather than as residue, because the paragraph under it now says
why it stands. The `signoff.sh` correction is right and worth having.

One blocking item, and it is the miss the round was set up to catch: `README.md:16` still says
`{:beam_mcp, "~> 0.1"}`. It resolves — I measured that rather than assuming it — so no build
breaks; what breaks is the signal. A consumer pinned `~> 0.1` at `0.1.0` crosses this release's
documented wire break on a routine `mix deps.update`, with nothing in their own file changing.
The README is in the Hex `files:` list and is the ex_doc landing page, so it is the artifact a
consumer reads before deciding how to depend on the package, and it currently recommends the one
requirement the `0.2.0` decision was made to let them avoid.

Two smaller record items: `FINDINGS.md:434` names the moved-file set wrongly in both directions,
and `FINDINGS.md:429`'s sentence accounts for six of the eight files its own command returns.

VERDICT: changes required
