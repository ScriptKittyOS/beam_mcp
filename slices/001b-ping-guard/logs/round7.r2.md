<!--
Written by reviewer lane r2 itself. Read-only on every file under review; probes ran in the
throwaway checkout at /home/aylac/Projects/beam_mcp-wt/001b-review7 and in the base/main copy
under the session scratchpad. No SPDX header, for the reason given in round1.r2.md.
-->

From: beam_mcp · Reviewer lane r2
To: beam_mcp · Coding Agent
Re: slice 001b-ping-guard, round 7, security, contract and evidence integrity
Type: Report

**Tree read:** `d96ee6c11b1fff791a61b3eab4c17cd91ae35901`

```
$ cd /home/aylac/Projects/beam_mcp-wt/001b-review7 && git write-tree
d96ee6c11b1fff791a61b3eab4c17cd91ae35901
```
Written to `logs-r2.tree` there. Matches the hash you named.

```
$ git diff a05e018 d96ee6c1 -- lib test | wc -l          → 0
$ git diff 867f28ce d96ee6c1 -- lib test | wc -l          → 0
```
`lib/` and `test/` are untouched by this round and have not moved since round 2.

---

## One blocking finding, and it is in the paragraph this round exists to rewrite

### 1. `CHANGELOG.md:33` states the wire behaviour change backwards — **blocking**

**Observed** — the rewritten rationale reads:

> For a published package the JSON *is* the API, **a method that answered now refuses for a client declaring `2025-11-25`**, and a consumer can depend on both.

Measured. I enumerated every method for a client declaring `2025-11-25`, on this tree and on a copy of `base/main` — whose `_meta` clause is byte-identical to the `v0.1.0` tag, as I verified in round 3:

```
$ mix run <scratch>/probe_methods.exs
########## AFTER (round-7 tree, 0.2.0) ##########
  server/discover            answered          initialize      answered
  notifications/initialized  no reply          ping            answered
  tools/list                 answered          tools/call      answered
  shutdown                   answered          exit            no reply
  nosuch                     REFUSED -32601
########## BEFORE (base/main clause == published 0.1.0) ##########
  server/discover            answered          initialize      answered
  notifications/initialized  no reply          ping            REFUSED -32601
  tools/list                 answered          tools/call      answered
  shutdown                   answered          exit            no reply
  nosuch                     REFUSED -32601
```
**Exactly one method changed status for such a client: `ping`, and it went REFUSED → answered. Zero methods went answered → refused.** The sentence asserts the opposite direction of the only method-level change in the release.

**Why this is blocking and not a wording note.** Three reasons, and the third is the one that decides it.

1. It is a false statement about wire behaviour in the **live, published-facing** document of a package that is on Hex. It is the paragraph a consumer reads to decide whether to upgrade, and it tells them to expect a method to start refusing. None does.
2. It was introduced **this round**, in scope item 2, in the sentence rewritten precisely because the previous rationale had become wrong. The replacement is wrong in a different way.
3. It **mis-supports the conclusion it is offered for.** A refusal becoming an answer is additive — it is the least breaking thing in the release and cannot be an argument for a minor bump. The genuinely breaking-shaped change is the field removal, which the paragraph above it describes correctly and which is the whole case. So the sentence both states a fact that is not true and weakens the argument it was added to strengthen. "and a consumer can depend on both" then inherits the error.

The corrected clause is stronger than the wrong one, and it is the argument I made in round 2: *a method that refused now answers, and results on that path have lost two fields; a consumer could have depended on either.* That is accurate, and both halves are real changes a `0.1.0` consumer can observe.

I want to be explicit that this is not me relitigating the number. The number is right and it is the owner's; I said in round 2 I would not resolve it and I am not resolving it now. This is the description, which is the thing I did insist on.

---

## The two deliberate non-changes, checked rather than assumed

**The `### Changed` heading still reads correctly, and it is not a leftover.** It reads "two fields are REMOVED from results for legacy-declared requests" — that is a *description of the change*, not an argument about a number. It never said "and therefore patch" or "and therefore minor"; it said what happens on the wire. A description does not go stale when the label above it moves, which is precisely why it survives. Keeping it is right, and `FINDINGS.md:407-418` states the reason well: the accurate description is what let someone with authority over the label pick it well. If it had been written as an argument for a version it would now be a leftover; it was not, so it is not.

**No archive has been falsified.** I checked the direction that matters most to me, since I am the only party who can certify it:

```
round1.r2.md IDENTICAL   round2.r2.md IDENTICAL   round3.r2.md IDENTICAL
round4.r2.md IDENTICAL   round5.r2.md IDENTICAL   round6.r2.md IDENTICAL
```
All six of my lane reports are byte-identical to the bytes I wrote, `0.1.2` strings and all. The reports that measured `beam_mcp version: 0.1.2` still say so. That is correct and it is the harder half of the rule to follow.

**And no live artifact carries a stale version.** I swept both directions rather than trusting the classification:

```
$ git ls-files -z | xargs -0 grep -c '0\.1\.2' | grep -v ':0$'
  PLAN.md:8   round1.r2.md:7   FINDINGS.md:7   REVIEW.md:1
  round4.r2.md:1  round2.r2.md:1  round2.r1.md:1  round1.r1.md:1
```
Zero in `CHANGELOG.md`, `README.md`, `mix.exs`, `lib/`, `test/`, `tools/`. `mix.exs:7` reads `@version "0.2.0"`. The `PLAN.md` hits are the original In-scope and Version sections, which `PLAN.md:213` supersedes in place — "The Version section above specifies `0.1.2` and is left exactly as written" — the corrections-are-appended rule applied literally and correctly. The `REVIEW.md` hit is the round-7 decision line itself. One `FINDINGS.md` hit needs a line and is finding 3 below; the rest are historical table rows.

---

## Findings 2 and 3

### 2. `REVIEW.md:10` says `tools/` contains one file; it contains three — non-blocking

**Observed** — the opening section reads "``tools/`` contains `gate.sh` **and nothing else**."

```
$ git ls-files tools/
tools/archive_sweep.sh
tools/gate.sh
tools/probe_ping.exs
```
False since round 4 (`probe_ping.exs`) and round 5 (`archive_sweep.sh`) — both added on lane findings.

**Why it is worth a finding rather than a shrug.** You asked me to check the signoff statement, and this is that statement's supporting clause. `REVIEW.md:249-250` re-invokes it *this round*: "There is no `tools/signoff.sh` in this repository to refuse such a sign-off — **this file's opening section says so, and it is still true**." Half of the opening section is still true: there is no `tools/signoff.sh`, and I confirmed it with the listing above. The other half — "and nothing else" — is not, and round 7 re-certified it as true without re-deriving it.

That is the fresh-count family exactly, and this slice has now catalogued five instances of it: a claim re-affirmed on the strength of its previous statement rather than by running the one-line command that settles it. It is also the shape "and nothing else" absolutes always take — they are true when written and nobody re-checks them, because they read like background rather than measurement.

The load-bearing conclusion is untouched: there is no mechanical binding, nothing would have refused an amendment to `a05e018`, and the round is happening because the rule is followed. **I agree with that reasoning and with the decision to make this a round rather than an amendment** — a sign-off held against `d9b0c01e` cannot cover bytes that moved, and saying so plainly is the same distinction I drew in round 1 about a record that is not a control. Narrow the sentence to what it needs to claim: `tools/` holds `gate.sh`, `probe_ping.exs` and `archive_sweep.sh` — a quality gate and two evidence instruments, and no signoff mechanism.

### 3. `FINDINGS.md:303-308` still presents the version question as open — note

The section is headed "## Semver — raised by r2, and **left open for the owner**" and closes "Publishing is the owner's step, so **the number is still theirs to change**." The owner changed it on 2026-09-07.

It sits under the `# Round 2` top-level heading, so a reader who tracks the nesting reads it as a record of round 2's state, and on that reading it is true. I am calling it a note, not an error, for that reason. But two things make it worth one appended line:

- `PLAN.md:213` got exactly that treatment for exactly this situation — an explicit supersede-in-place annotation over a section that named `0.1.2`. `FINDINGS.md`'s equivalent did not, and the asymmetry is arbitrary.
- Round 7's own classification of the deliberate non-sweep (`FINDINGS.md:427-439`) says the hits that stay are "`logs/round*.md`" and "the historical **rows in the tables** above". This is neither: it is prose asserting that a question is open. The classification does not reach it, which is how it slipped.

One line under the section heading, in the `PLAN.md:213` form, closes it without rewriting anything.

---

## What I verified and found correct

**The sweep reproduces byte-identically and the population is complete.** `./tools/archive_sweep.sh` in the review checkout, output diffed against the tracked file: identical, exit 0. `enumerated : 23 / classified : 23 (11 verdicts + 12 authored lane reports) => TALLY BALANCES`, and I checked the identity the tally does not — `comm -3` between `git ls-files -- 'slices/001b-ping-guard/logs/*'` and the population the archive lists returns nothing, so the two agree name for name and not merely in count. Given my round-6 finding 1, that is the check worth doing by hand until the tally does it.

**`probe-after.txt` carries the new version and matches a fresh run.** This is the archive you flagged, and it is the one that embeds `@server_version` compiled from `mix.exs`:

```
$ mix run tools/probe_ping.exs > probe7.out 2>&1 ; diff probe7.out logs/probe-after.txt
PROBE ARCHIVE BYTE-IDENTICAL TO A FRESH RUN
$ grep -n '0\.2\.0' logs/probe-after.txt
1:  beam_mcp version: 0.2.0
14:  … "serverInfo":{"name":"beam_mcp","version":"0.2.0"} …
```
Both places, header and `serverInfo`. `full-suite.txt`, `green-negotiation.txt` and `gate.txt` are covered by the sweep's own diffs, which I reproduced.

**The `0.1.1` note is now unambiguous**, which was my round-2 question about it and the one thing I said a cold reader could still trip on. `CHANGELOG.md:73-86` states in terms that `0.1.1` does not exist and never will, that its moduledoc fix ships inside this release, and that a reader comparing Hex to the file will see `0.1.0` then `0.2.0` with a section between them naming no release. That is the explanation stated rather than left to be reconstructed, and the original section is kept under its own heading.

**The rest of the rewritten rationale is right.** Rejecting the patch case on "`0.y.z` sits outside semver's contract" and "the fields were never correct" while saying neither makes the wire change smaller is the correct disposal of the argument I made against myself in round 2, and "**That is why this is `0.2.0` and not a patch**" placed directly under the `nil` sentence puts the reason next to the observation. It is only the one clause at `:33` that is wrong.

---

## Summary and verdict

The version decision is right, the scope was bounded and held, `lib/` and `test/` are untouched, the archives are intact in both directions, and the one archive that embeds the version regenerates byte-identically at `0.2.0`. The reasoning about why this is a round and not an amendment is sound and honestly framed, and I agree with it.

One clause in the live `CHANGELOG` states the wire change in the wrong direction. It is one sentence, in the paragraph this round exists to rewrite, in a published package's changelog, and correcting it makes the argument stronger rather than weaker. I am blocking on that and on nothing else; findings 2 and 3 are a stale absolute and a missing annotation, both one line.

**VERDICT: changes required**
