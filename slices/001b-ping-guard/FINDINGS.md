<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Slice 001b — FINDINGS

Every count below is quoted from the output of the named command. Every log file under
`logs/` was written by the command that produced it (`… | tee logs/<name>.txt`), so it is an
archive in the sense `CONVENTIONS.md` requires — the bytes are the command's bytes, not a
transcription.

Worktree: `/home/aylac/Projects/beam_mcp-wt/001b-ping-guard`, branch `slice/001b-ping-guard`,
off `main` at `5d8d1ae`, with its own `_build` and `deps`. The canonical clone was not written
to.

## Finding 1 — `ping` refused under `2025-11-25`. SCR-257. Live in published `0.1.0`.

`lib/beam_mcp/server.ex:120-135` at `5d8d1ae`. The `_meta` clause's `cond` branched on
`message["method"] == "ping"` with no comparison against `@modern_version`, while the comment
above it named `2026-07-28`.

**Observed** — `mix run <scratchpad>/probe_ping.exs`, `mix.exs` version `0.1.1`:

    ping + _meta 2026-07-28
      -> {"error":{"code":-32601,"message":"Method not found: ping"},"id":1,"jsonrpc":"2.0"}
    ping + _meta 2025-11-25
      -> {"error":{"code":-32601,"message":"Method not found: ping"},"id":1,"jsonrpc":"2.0"}
    ping + _meta, no version key
      -> {"id":1,"jsonrpc":"2.0","result":{}}
    ping bare
      -> {"id":1,"jsonrpc":"2.0","result":{}}

**Expected**: line 2 returns `{"result":{}}`. `ping` exists in `2025-11-25`; this server
advertises `2025-11-25` in `server/discover` and lists it in the `-32022` `supported` payload.

**Boundary, measured rather than assumed**: line 3. A `_meta` carrying no
`io.modelcontextprotocol/protocolVersion` does not match the clause head and falls through to
the bare handler. The defect is specific to a `_meta` that names a revision.

## Finding 2 — the same clause modernised every result, on the same version-blind basis

Not in SCR-257; found while measuring finding 1.

**Observed**, same command and run:

    tools/list + _meta 2025-11-25
      -> {"id":2,"jsonrpc":"2.0","result":{"_meta":{"io.modelcontextprotocol/serverInfo":
         {"name":"beam_mcp","version":"0.1.1"}},"resultType":"complete","tools":[...]}}

**Expected**: no `resultType`, no `_meta`. Both are `2026-07-28` additions.

**Corrected in round 2, r1 finding 1c.** Round 1 argued this from the changelog's item 8 —
clients "**MUST** treat results from earlier-protocol servers that omit the field as
`complete`" — and said that MUST "is only coherent if an earlier-revision result omits it".
That is an inference, and it was set next to two genuinely quoted MUSTs where it read as a
third. It is not one: item 8's MUST is addressed to **clients** and governs how they handle
*omission*, not whether a server may *emit*. r1 also checked `2025-11-25`'s own base-protocol
page, which says a result "**MAY** follow any JSON object structure" — so keeping the two
fields would have violated no normative requirement in either revision.

The corrected basis: emitting `resultType` and a modern `serverInfo` on a result answering a
request that declared `2025-11-25` announces a revision the client did not ask for. The fix
wins on **honesty**, not on conformance. The distinction matters because a conformance claim
is checkable against the spec and this one would have failed.

Same root cause as finding 1 — one `cond` that never reads `version` — so fixed in the same
change rather than filed onward. Fixing only `ping` would have left the clause version-blind.

## The red, before any edit to `lib/`

    $ mix test test/beam_mcp/negotiation_test.exs
    12 tests, 2 failures
    exit=2

Full output: `logs/red.txt`, written by the command.

**Corrected in round 2, r1 finding 6.1.** The first version of this sentence read "the ten
pre-existing tests passed, so the red is the two additions". Both numbers were typed fresh and
both are wrong, which is the exact thing `CONVENTIONS.md` forbids. Derived rather than typed:

    $ git show base/main:test/beam_mcp/negotiation_test.exs | grep -c '^\s*test '
    9
    $ grep -c '^\s*test ' test/beam_mcp/negotiation_test.exs      # at the round-1 index
    12

**Nine** pre-existing tests, **three** additions. Two of the three are red at `base/main`; the
third (`a 2026-07-28 result carries resultType and serverInfo _meta`) passes there and is a
regression guard, not a red. The old sentence's arithmetic was self-consistent and landed on
the right total, which is why it survived being written.

Round 2 added three more tests — two of them mutation-killed, the third an unscored guard,
as corrected below — for a file total of 15.

## Green

    $ mix test test/beam_mcp/negotiation_test.exs
    12 tests, 0 failures
    exit=0

    $ mix test
    36 tests, 0 failures

**Those two counts are the ROUND-1 measurement and the archives no longer hold them.** Round 2
added three tests and re-took both logs, so `logs/green-negotiation.txt` now reads
`15 tests, 0 failures` and `logs/full-suite.txt` `39 tests, 0 failures`. The round-1 numbers are
kept here because this section is the round-1 record; the citations to the log files are removed
from them, because a citation pointing at bytes that say something else is worse than no
citation. r2 finding 2 — and it is the same defect as r1's 6.1, in the same file, one round
later: re-taking the evidence and leaving the quotation behind.

    $ mix run <scratchpad>/probe_ping.exs          # logs/probe-after.txt
    ping + _meta 2026-07-28        -> {"error":{"code":-32601,...}}      unchanged
    ping + _meta 2025-11-25        -> {"id":1,"jsonrpc":"2.0","result":{}}
    ping + _meta, no version key   -> {"id":1,"jsonrpc":"2.0","result":{}}   unchanged
    ping bare                      -> {"id":1,"jsonrpc":"2.0","result":{}}   unchanged
    tools/list + _meta 2025-11-25  -> {"result":{"tools":[...]}}          no resultType, no _meta
    tools/list + _meta 2026-07-28  -> {"result":{"_meta":{...},"resultType":"complete",...}}  unchanged

The pre-existing test "a modern ping is refused" was **not** edited and still passes, so
acceptance criterion 2 is met by an unmodified assertion. It is at `negotiation_test.exs:145`
at `base/main` and moves down as lines are inserted above it; cited by name rather than by line
because r2 (finding 7) followed the number into the merged tree and landed on a different test.
`git diff base/main HEAD -- test/` shows no `-` line anywhere in that describe block.

## Gate

    $ ./tools/gate.sh                              # logs/gate.txt
    == beam_mcp gate ==
      format                     pass
      compile                    pass
      test                       pass
      credo                      pass
      reuse                      pass (17 commentable files)
      licence files              pass
    Gate OK.
    gate exit=0

Read per step, not by exit code alone: all six lines read `pass`.

## Scripted edits, match counts asserted

**Six** edits in round 1, each applied by a Python replace that asserted its count before and
after and would have raised rather than no-opped. (Round 1 said "four" over a six-row table —
r1 finding 6.1. Corrected, not rewritten: the table below was always the authority.)

| edit | file | before | after |
|---|---|---|---|
| `legacy_meta/2` helper | `test/beam_mcp/negotiation_test.exs` | 1 | 1 present |
| three new tests | `test/beam_mcp/negotiation_test.exs` | 1 | old 0, new 1 each |
| the `_meta` clause | `lib/beam_mcp/server.ex` | 1 | old 0, new 1 |
| era table | `README.md` | 1 | old 0, new 1 |
| `@version` | `mix.exs` | 1 | old 0, new 1 |
| `0.1.2` section | `CHANGELOG.md` | 1 | 0.1.2 = 1, 0.1.1 = 1 (kept) |

## Recorded, not fixed — out of scope, filed onward

1. **`ttlMs` and `cacheScope` are missing from `tools/list` results.** `2026-07-28` requires
   both on `tools/list`, `prompts/list`, `resources/list`, `resources/read` and
   `resources/templates/list` via `CacheableResult` (changelog, minor change 5).
   `modernise/2` at `lib/beam_mcp/server.ex` adds `resultType` and `_meta` `serverInfo` and
   neither of these. Pre-existing since slice 001 and unrelated to the version branch.
   Observed in `logs/probe-after.txt`: the `2026-07-28` `tools/list` result carries neither.
2. **A `_meta` with no version key is served bare.** Line 3 of finding 1's measurement. That
   is the no-era-established path and belongs to SCR-255, not here.

---

# Round 2 — what the two reviewer lanes changed

Both lanes read tree `a42f1b1e82599b203df0afcaaa8639203fd663d7`, which equalled `git write-tree`
on the staged index. Both returned **changes required**. **Neither raised a finding against
`lib/`'s logic**: r2 states "The `lib/` change is correct, minimal, and I found nothing to fix
in it", and r1 that "the fix itself is correct, minimal, well-argued against the fetched spec".
Every change below is documentation, evidence, or coverage.

## Blocking — one, from r1 (finding 2.1)

`lib/beam_mcp/server.ex:16-18`, the `@moduledoc`, said a `_meta` request "is served statelessly
under **the modern revision**" — the exact rule this slice deletes. The inline comment and the
README were updated in round 1; the moduledoc, which is the hexdocs front page for the
package's principal module, was missed. That is the same doc/code mismatch as the defect the
slice exists to close, one file up. Fixed, and the moduledoc now also names the two methods
matched before the era switch.

## Coverage — r1 finding 4, and it was a real gap

`send_msg/1` discards the returned state, so **every** test in the file threw the state away and
nothing could catch a branch returning the wrong one. `shutdown` is the only request method that
changes state and it reaches both branches. Three tests added. **Two of the three are
mutation-killed; the third is not, and cannot be** — nothing on the `ping` path writes state, so
falsifying it would mean inventing a write rather than perturbing an existing one. It is a guard
against a write that does not exist, and it is not scored. Round 2 first claimed all three were
"scored by mutation" over a single mutant; both lanes caught it (r1 finding 1, r2 finding 4) and
both independently ran the second mutation. Corrected, and both mutations are archived **raw** at
`logs/mutation-a.txt` and `logs/mutation-b.txt` — `mix test … > file 2>&1`, no pipe and no
filter, each carrying the seed line, the progress dots, the whole failure block including
`code:` and `stacktrace:`, and the `Finished in …` line.

Round 3 first wrote a single `logs/mutation.txt` produced by a `{ … } | tee` whose `mix test`
was piped through `grep -E`, and labelled it "written by the commands that ran them". It was a
curated extract: it dropped the seed line and **all five** indented lines of the failure block
(the `1) test …` header survived; the five lines under it did not) —
including the assertion message that identifies *which* assertion failed. r2 caught it (round 3,
blocking) and declined to soften a finding it had made blocking one round earlier on a different
file. That file is deleted and replaced by the two raw captures. **Third instance in this slice
of the same rule.**

The scoring below is a hand-written summary and is labelled as one — it is not captured output
and does not claim to be:

    mutation: the @legacy_version branch returns {state, response} instead of the recursion's tuple
    match count before = 1, old remaining after = 0        # asserted applied
    $ mix compile --force                                  # applied before scoring, not after
    $ mix test test/beam_mcp/negotiation_test.exs
      1) test ... shutdown declaring 2025-11-25 through _meta still sets shutdown?
    15 tests, 1 failure
    REAL_EXIT=2

The mutant is killed. A test that passes over an unapplied mutant would have been discarded, not
scored — the rule from SCR-259.

## A second `lib/` change in round 2, which no lane asked for — disclosed late

`lib/beam_mcp/server.ex`: `{next, modernise(response, state)}` became
`{next, modernise(response, next)}`, on r1's round-1 **note** 2.3. Round 2's opening sentence
said this section held one `lib/` change, the moduledoc, and that "every change below is
documentation, evidence, or coverage". That was false of the tree it shipped, and r2 (finding 3)
caught it by mutation rather than by reading the record:

    MUTANT: modernise reads the pre-recursion state (this change, reverted)
    applied: before=1 old_after=0 new_after=1
    15 tests, 0 failures
    REAL_EXIT=0                                    # the mutant SURVIVES

**The change is unfalsifiable today and is kept anyway.** `modernise/2` reads only
`server_name`, which no handler mutates, so `state` and `next` are indistinguishable here — the
code comment says exactly that. It is defensive correctness against a latent trap, not a fix. It
is recorded because an undisclosed edit is a defect in the record whether or not it is a defect
in the code, and because a surviving mutant that is *correctly* a survivor still has to be
reported as one.

## Evidence — r2 finding 1 / r1 finding 6.3

`logs/probe-after.txt` was captured after the `lib/` edit and **before** the `mix.exs` bump, so
it reported `beam_mcp version: 0.1.1` and archived a `serverInfo` carrying `0.1.1` — a version
string that exists nowhere in the committed bytes, in the one file recording what the modern
envelope emits. The bytes were genuinely the command's; the tree they measured was not the tree
being shipped. **Re-taken against the final tree**, and `logs/full-suite.txt` and
`logs/green-negotiation.txt` re-taken with it.

## Prose that claimed more than the code keeps — r1 2.2, r2 2 and 4

Round 1's new README paragraph said the declared revision "decides the method table and the
result envelope". Both lanes found reachable counterexamples, because `server/discover` and
`initialize` are matched **before** the `_meta` clause:

    modern _meta + server/discover
      -> {"result":{"capabilities":{...},"protocolVersions":[...],"serverInfo":{...}}}   # no resultType

`server/discover` is **mandatory** in `2026-07-28` and its result carries no `resultType`, which
the same revision requires on every result. Round 1 replaced a paragraph that stated the intended
rule rather than the shipped one with a paragraph that had the same property — which is the
defect this slice is about, committed a second time in the fix for it. The README now carries
both exceptions explicitly, and the `server/discover` gap is recorded below.

## Recorded in round 2, not fixed — all out of scope, all filed or listed

3. **`server/discover` results carry no `resultType`.** Mandatory method, required field,
   pre-existing since slice 001. Same family as the `ttlMs`/`cacheScope` gap and belongs with it.
4. **The session is tracked and never enforced.** `grep -rn 'initialized?' lib/` returns four
   hits: one type, one initialiser, two writes, **no read**. A bare `tools/call` dispatches. That
   is SCR-255, and it is now stated in the README rather than left as tribal knowledge — r2's
   point that a requirement nobody is told about is not a control.
5. **`-32022` echoes arbitrary caller-supplied JSON** back in `data.requested`
   (`server.ex`, `unsupported_version/2`). Maps, lists and booleans are echoed verbatim.
   Reflection is to the same caller and amplification is ~1x, so not a defect — recorded because
   the new `_other` branch is where it now lives and a future change that logs or forwards that
   payload would inherit it. Byte-identical at `base/main`.
6. **The gate's REUSE population is a hand-written glob** (`git ls-files -- '*.ex' '*.exs' '*.sh'
   '*.yml'`) under a comment reading "every tracked file that can carry a comment". `.md` is
   outside it, and two tracked root `.md` files carry no SPDX header. `.txt` being outside is
   **correct** — an SPDX header prepended to a `tee`d archive would stop the bytes being the
   command's bytes.

   **The headerless population is derived, not counted by hand** (r2 round 3, finding 2 — which
   found the hand-written number four files short and observed it would be six short once the
   round-3 reports landed):

       $ git ls-files -- '*.md' | while read -r f; do \
           head -5 "$f" | grep -q 'SPDX-License-Identifier' || echo "  $f"; done

   **The `curl -o` rationale does not cover all of them, and that is the point.** It covers the
   three `logs/spec-*.md` files exactly — fetched bytes, which a header would corrupt. It does
   **not** cover the reviewer-lane reports under `logs/`, which are authored prose: ordinary
   `.md` files that this tree's convention would header and that the gate cannot see either way.
   So the gap has two kinds of file in it and only one kind has a defence. Filed rather than
   fixed.
7. **`tools/gate.sh`'s `licence files` line is not printed at all when an earlier step failed**
   (`[ "$fail" -eq 0 ] && note …`), so a reader following "read the step's line, not the exit
   code" gets an absent verdict rather than a failing one. Filed rather than fixed.

## Semver — raised by r2, and left open for the owner

r2 accepted `0.1.2` but insisted the removal be labelled, which it now is under its own
`### Changed` head. Its argument for `0.2.0` is recorded there rather than resolved here: for a
published package the wire JSON is the API, and two fields disappear from a path that produced
them in `0.1.0`. Publishing is the owner's step, so the number is still theirs to change.

## Round 2 counts, quoted

    $ mix test test/beam_mcp/negotiation_test.exs      15 tests, 0 failures
    $ mix test                                         39 tests, 0 failures

---

# Rounds 3 and 4 — the same rule, three times, in the file that claims it

This section exists because r2 (round 3, finding 3) pointed out that the evidence log recorded
none of it: `FINDINGS.md` opens by asserting every file under `logs/` is an archive written by
its command, and the one round where that was untrue was missing from the file making the claim.

## The recurrence, stated plainly

| # | round | file | what was wrong | caught by |
|---|---|---|---|---|
| 1 | 1 | `probe-after.txt` | genuine bytes, but of a tree that was not being shipped (`0.1.1`) | r2 finding 1, r1 6.3 |
| 2 | 2 | `full-suite.txt`, `green-negotiation.txt` | re-taken through `\| tail -4`; `mix test`'s seed line stripped | r2, **blocking** |
| 3 | 3 | `mutation.txt` | `{ … } \| tee` with `mix test` piped through `grep -E`; seed line, progress dots, `Finished in`, and **all five** indented failure-block lines dropped | r2, **blocking** |

Each fix introduced the next defect. Round 2's re-take was the fix for #1 and produced #2.
Round 3's `mutation.txt` was added to close the family and was #3.

**`FINDINGS.md:234-235` is corrected by this section rather than rewritten.** It reads that the
two logs were "re-taken against the final tree", which is true and is the record of the re-take
that turned out to be filtered. They were re-taken **twice**: once in round 2, filtered, and
again in round 3 with `> file 2>&1`. The first re-take is the sharpest finding in the slice.

**A fourth hand-written count, found inside the table that catalogues hand-written counts.**
r1 (round 4, finding 2) measured the deleted `mutation.txt` against the raw capture now in the
tree: the `1) test …` header survived and **all five** indented lines were dropped, not four of
five. The wrong figure appeared twice, once in the instance-table row for this exact family.
Corrected above. r1's round-3 figure of thirteen lines per block is the same measurement taken
from the other end and was right.

**The tally that stood here is deleted rather than corrected**, and that is the point of it.
It read "four fresh counts across five rounds" while `logs/round5.r1.md` heads its own finding
"The fifth count" and the slice ran six rounds — a typed number, wrong in both figures,
**inside the paragraph arguing that a typed count is indistinguishable from a derived one.**
r1 found it (round 6). Replacing it with a freshly typed "five across six" would repeat the
defect in the act of fixing it, and no command in this tree derives the number, so the honest
move is to state the fact without the count: every one of these was caught by a lane, and none
by me. The instances themselves are enumerated in the table above, where they can be counted by
a reader rather than asserted by the author.

**And the fourth did not originate with me — it came from a reviewer report, and I adopted it
without re-deriving.** r2 raised this against itself in round 5 (finding 4): the "four of five"
figure was written in r2's own round-3 report, in the sentence explaining why its blocking
finding was blocking. I folded that number into `FINDINGS.md` and into the instance table on
the strength of its source, and r1 caught it a round later.

The lesson is therefore not "be careful with numbers", and not even "derive your own counts". It
is that **a count is underived no matter whose page it is on.** A figure in an adversarial
reviewer's report is exactly as unverified as one in mine; taking it on trust because of who
wrote it is how this one survived two rounds and reached the table that catalogues this family.
`CONVENTIONS.md` requires the command rather than the number, and that requirement does not
weaken when the number arrives from someone checking your work.

## Why counting is not checking, which is the transferable part

r1 re-ran both commands in round 2 and compared **counts**. The counts were right, so it passed.
r2 compared **bytes** — `diff` against a fresh run, `1d0` — and ruled out a configuration
explanation (`--seed 0`, `test_helper.exs`) before calling it. Same evidence, same two lanes, one
method finds it and the other cannot. For anything labelled an archive, diff the bytes.

r2 also declined to soften #3 to a note, and said why: an identical defect on a different file
cannot be blocking one round and a note the next, "or the standard is whatever the reviewer feels
like that morning". Recorded because that is the reason the third instance was caught at all.

## Round 4 — what changed

1. `logs/mutation.txt` **deleted**; replaced by `logs/mutation-a.txt` and `logs/mutation-b.txt`,
   each `mix test … > file 2>&1`, no pipe, no filter. Both mutations re-run from a fresh copy of
   the tree, match counts asserted before and after, `mix compile --force` before scoring per
   SCR-259. Mutation A kills the legacy `shutdown` test; B kills the modern one; each run reports
   `15 tests, 1 failure`, real exit 2.
2. The label "written by the commands that ran them" removed from `FINDINGS.md` and `REVIEW.md`;
   the scoring table is now marked a hand-written summary, which it always was.
3. The `.md` SPDX-gap item now derives its population by command instead of carrying a
   hand-written three, and distinguishes fetched bytes (a header would corrupt them) from the
   authored lane reports (no such defence).
4. `REVIEW.md`'s tree-hash list extended to round 3 — if the list is the binding, it carries
   every round it binds.

**No change to `lib/` or `test/` in rounds 3 or 4.** Both lanes' `lib/` conclusions stand on
bytes they read at `867f28ce`.
