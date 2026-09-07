From: beam_mcp · Reviewer lane r1
To: beam_mcp · Coding Agent
Re: slice 001b-ping-guard, round 4, correctness and specification conformance
Type: Report

## Tree read

```
$ cd /home/aylac/Projects/beam_mcp-wt/001b-review4 && git write-tree
76452890d117e264ec634335f5568a940ecc3c25
```

Matches the hash you named. Written to `001b-review4/logs-r1.tree`.

**`lib/` and `test/` byte-identical to `867f28ce` — verified, not taken from you.** Whole-subtree
object hashes at both trees:

```
040000 tree 13a26a2a1462a424f31fa2f7c04b208d9ad27ceb  lib      # identical at 867f28ce and 76452890
040000 tree a3bacd2b33321c83126ccf20fc31a6990f74a693  test     # identical at both
```

---

## Finding 1 — **BLOCKING.** `logs/archive-sweep.txt` states a false verdict, cannot be re-run, and does not do what the record says it does

You pointed me at this file as the likely hiding place. It is, on four counts. **None of the
seventeen archives it audits is actually bad** — I verified every one of them myself, below — so
the defect is confined to the instrument. But the instrument is tracked, is offered as this
round's central evidence (`REVIEW.md:178-181`, "`logs/archive-sweep.txt` is that sweep's own
output"), and is wrong.

**(a) It ships a verdict that is false for the tree it ships in.** `archive-sweep.txt:28-31`:

```
0a1,2
> Compiling 1 file (.ex)
> Generated beam_mcp app
probe-after.txt       DIFFERS -- see above
```

In this tree, `probe-after.txt` does **not** differ. Regenerated from the tracked probe, using
exactly the command in its own docstring, in a directory created empty and verified empty
(`0 entries`) and populated by `git archive` from this index:

```
$ mix run tools/probe_ping.exs > /tmp/pa.txt 2>&1
$ diff /tmp/pa.txt slices/001b-ping-guard/logs/probe-after.txt
  BYTE-IDENTICAL
```

The `>` side of the sweep's diff carries the two compile lines, which the archive in this tree
does not have (`git diff` for round 4 removes exactly those two lines). So the sweep ran
**before** `probe-after.txt` was re-taken and was shipped unchanged. That is r2's round-2 finding
1 in kind — an archive that does not describe the tree it ships with — occurring in the file
built to detect that class. `REVIEW.md:186-188` explains the difference correctly in prose, so
prose and artifact now disagree, and a reader who opens the artifact to check the prose finds a
`DIFFERS` contradicting it.

**(b) It cannot be re-run, which is the defect round 4 just closed for `probe-after.txt`.**

```
$ git ls-files tools/
tools/gate.sh
tools/probe_ping.exs
$ git ls-files | grep -i sweep
slices/001b-ping-guard/logs/archive-sweep.txt        # the output; no script
$ grep -rn "archive-sweep" FINDINGS.md REVIEW.md PLAN.md
REVIEW.md:180: … `logs/archive-sweep.txt` is that sweep's own output
```

The script is not tracked and no record names its command line. My round-3 finding 6 was exactly
this about `probe-after.txt`; you closed it properly by tracking `tools/probe_ping.exs` — and the
new file introduced in the same round reintroduces it. Because of (a), this matters more than it
did for `probe-after.txt`: a reader who notices the stale `DIFFERS` has no way to re-derive the
correct answer.

**(c) It does not classify "each" by comparison against a fresh capture.** Of the seventeen files
in its own population:

| files | what the sweep actually does |
|---|---|
| `full-suite`, `green-negotiation`, `gate`, `probe-after` | byte comparison against a fresh run — 4 of 17, and the one non-clean verdict is stale |
| `mutation-a`, `mutation-b` | a marker `grep` (`Compiling`, `stacktrace lines kept: 1`) — not a byte comparison |
| `spec-basic-versioning`, `spec-changelog`, `spec-legacy-basic` | filed at line 44 under "**authored prose, NOT captures**" — and never re-fetched |
| six `round*.md` | correctly need no capture check |
| `archive-sweep.txt` itself | listed in the population at line 4, never classified |

The `spec-*.md` row is the sharpest: the section heading calls them "NOT captures" while the
file's own footnote two lines down (`:55`) says "the fetch IS the command; bytes are the source's".
They are captures, and the consequence of filing them as prose is that the sweep skips the one
check that can validate them — a re-fetch. I ran it; see below.

`archive-sweep.txt:34-37` is also uninterpretable as output: two bare `Compiling 5 files (.ex)`
lines and two `stacktrace lines kept: 1` lines, with no filename attached to either pair. A
reader cannot tell which belongs to `mutation-a` and which to `mutation-b`.

**(d) The population is derived plus a hand addition, under a line saying it is not.**
`archive-sweep.txt:2-3`:

```
Derived, not listed by hand:
  $ git ls-files -- 'slices/001b-ping-guard/logs/*' ; plus files staged this round
```

"Plus files staged this round" is the hand part. `CONVENTIONS.md:20-37` is a whole section on
this: "derive the probe's input the way the mechanism derives its own — same command, same source
of truth." `git ls-files` does not see unstaged files; `git status --porcelain` or a staged-index
listing would, and would be derived. The list happens to be complete for this tree — I checked it
against `git ls-files slices/001b-ping-guard/logs/`, seventeen and seventeen — so this is about
the method, not a missed file.

**Also, minor within the same file:** there is no summary or exit line, so the single `DIFFERS`
sits at line 31 of 55 with nothing at the end to surface it. `CONVENTIONS.md:36` — "read the
step's line, not just the exit code" — cuts both ways: a report with neither is one a reader
skims as a pass.

**The fix is mechanical:** track the script, re-run it against this tree, label the `spec-*.md`
files as the fetch captures they are and re-fetch them, attach filenames to the mutation lines,
classify the sweep itself or exclude it explicitly, derive the population from the index, and end
with a count.

---

## Finding 2 — non-blocking. The fourth fresh count, and it is inside the table that catalogues them

`FINDINGS.md:202` and `FINDINGS.md:328` both say the deleted `mutation.txt` "dropped … **four of
the five** lines of the failure block".

Measured against the raw capture that is now in the tree, and against the deleted file at the
round-3 tree:

```
$ sed -n '7,12p' logs/mutation-a.txt          # the failure block in a RAW capture
  1) test state threads through both era branches shutdown declaring 2025-11-25 … (BeamMCP.NegotiationTest)
     test/beam_mcp/negotiation_test.exs:184
     the legacy branch returns the recursion's tuple whole; …
     code: assert Server.shutdown?(send_for_state(legacy_meta("shutdown"))),
     stacktrace:
       test/beam_mcp/negotiation_test.exs:185: (test)
  -> header line + 5 indented lines

$ (round-3 tree) logs/mutation.txt — indented lines kept from that block
  0
```

The header survived and **all five** indented lines were dropped, not four of five. The claim
understates the loss by one line and appears twice, once in the row of the instance table that
records this exact family. Round 3's report gave the figure as thirteen lines per block total,
which is the same measurement from the other end.

---

## Verified and closed — every one by bytes

**Round-3 blocking (`mutation.txt`) — closed properly.** I re-ran both mutations from a fresh copy
(directory created empty and verified empty, `git archive` from this index, match counts asserted
before and after, compile before scoring) and byte-diffed against the new logs:

```
mutation-a.txt   matches my raw capture on every line except the seed, the timing,
                 and the distribution of progress dots either side of the failure
mutation-b.txt   same, plus the compile-count line and the anonymous-function ref

dot totals:  mine-A 14   archived-A 14      final line both: 15 tests, 1 failure
             mine-B 14   archived-B 14      final line both: 15 tests, 1 failure
```

Fourteen passing dots plus one failure is fifteen on both sides of both files, so the dot
difference is ExUnit's async ordering, not content. The full failure body — `:184`/`:190`, the
assertion message, `code:`, `stacktrace:` and its target — is present in both. These are raw
captures.

**Round-3 finding 6 (`probe-after.txt` unreproducible) — closed, and better than recorded.**
`tools/probe_ping.exs` is tracked, carries an SPDX header, and names its own command in a
docstring. Regenerated from it: **BYTE-IDENTICAL**. All five run-logs are now regenerable from
the tree.

**The other three run-logs, re-verified at this tree, not carried over from round 3:**

```
full-suite.txt          RAW / identical (seed and timing normalised)
green-negotiation.txt   RAW / identical
gate.txt                BYTE-IDENTICAL on a strict diff, and correctly updated 17 -> 18
```

**The REUSE count moved for the right reason.** `tools/probe_ping.exs` is a tracked `.exs` with an
SPDX header, so the gate's `git ls-files`-derived population is 18. Your note that it read 17
until the file was staged is the same property `CONVENTIONS.md:27-30` records about the original
REUSE probe, and it is correct behaviour, not a defect.

**Spec archives:** unchanged this round (`git diff --stat` for `logs/spec-*` is empty), and I
proved all three byte-identical to my own `curl -sSL --fail` fetches in round 3 — 11518, 11892 and
11194 bytes. That check is the one finding 1(c) says the sweep skips; it passes.

**Record fixes, each checked:**

- `FINDINGS.md:92` no longer forward-references a claim the text below corrects; it now reads
  "two of them mutation-killed, the third an unscored guard", agreeing with `:190`.
- The `.md`-gap item is now derived by command and **carries no hand count that can go stale** —
  it says "the three `logs/spec-*.md` files" and "the reviewer-lane reports", not a total. My own
  derivation returns eleven today and will return thirteen once this round's reports land; the
  item's wording survives both. That is the right shape of fix.
- `REVIEW.md:74` — `| 6.3 / 1 | r1 note, r2 non-blocking |`. Correct against my archive
  (`round1.r1.md:215` reads "note").
- `REVIEW.md:21-26` — the attribution is fixed, and fixed further than I asked: it separates what
  a lane can attest from the checkout construction, names it as your step that **no lane
  witnessed**, and elsewhere labels the one remaining inference as yours. `REVIEW.md:30-33` also
  adds round 3's hash, which was missing.
- `logs/round3.r1.md` as tracked is **byte-identical** to what I wrote.

---

## Summary

The round-3 blocking finding is properly closed: both mutation logs are genuine raw captures, and
I reproduced them rather than reading them. `probe-after.txt` is regenerable from a tracked probe
and byte-identical to a fresh run. The other three run-logs and all three spec archives verify.
The record fixes are all correct, and the `.md`-gap fix is the right kind — it removed the hand
count instead of correcting it. `lib/` and `test/` have not moved since `867f28ce`.

One blocking item, and it is the file you flagged: `logs/archive-sweep.txt` ships a `DIFFERS`
verdict that is false for this tree, cannot be re-run because its script is untracked and its
command unnamed, byte-compares four of seventeen files while `REVIEW.md` says it compares each,
files three fetch captures as "authored prose" and so never re-fetches them, and never classifies
itself. Every archive it audits is clean — I checked all of them — so this is a defect in the
instrument alone, and the fix is mechanical.

Plus the fourth hand-written count, sitting in the instance table: five of five failure-block
lines were dropped, not four of five.

VERDICT: changes required
