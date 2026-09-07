From: beam_mcp · Reviewer lane r1
To: beam_mcp · Coding Agent
Re: slice 001b-ping-guard, round 8, correctness and specification conformance
Type: Report

## Tree read

```
$ cd /home/aylac/Projects/beam_mcp-wt/001b-review8 && git write-tree
072cf981c6a97973cf9943847ddf818d483b8603
```

Matches; `git status --short` clean. Written to `001b-review8/logs-r1.tree`.

## The base, re-derived rather than taken from you

Every claim in your message about the rebase holds:

```
  a05e018        tree=a866ad8de07a2706735c025e98a3305c083e011b
  origin/main    commit=0332c41  tree=a866ad8de07a2706735c025e98a3305c083e011b
  git diff a05e018 origin/main   -> empty
  is a05e018 an ancestor of origin/main?  NO
  origin/main log: 0332c41 <- 5d8d1ae <- 38e3177
```

Identical trees, empty diff, and `a05e018` genuinely is not an ancestor — the rebase replayed the
one commit onto `5d8d1ae`, the same parent this slice started from, so the content landed exactly
and the local commit is a duplicate. That is the merge-method rule behaving as documented, and it
is worth noting that the thing which makes it safe to check is that the *tree* hash is the
identity, not the commit hash.

**`lib/` is untouched and `test/` is purely additive**, verified by object hash rather than by
diff alone:

```
  lib  at origin/main: 13a26a2a1462a424f31fa2f7c04b208d9ad27ceb   here: 13a26a2a…  (identical)
  test at origin/main: a3bacd2b33321c83126ccf20fc31a6990f74a693   here: 2c9bbea3…
  $ git diff 0332c41 HEAD --name-status -- test
  A  test/beam_mcp/readme_claims_test.exs                        (one file, added, nothing else)
```

So every `lib/` conclusion both lanes have reached still rests on bytes we read, and the only
executable change in this round is a new test file, which I have reviewed as code below rather
than only reproducing.

---

## My round-7 finding is not merely fixed; it is now mechanically prevented

`README.md:16` reads `{:beam_mcp, "~> 0.2"}`. More than that: I put the defect back and the suite
went red.

```
MUT 1: {:beam_mcp, "~> 0.2"} -> {:beam_mcp, "~> 0.1"}   (before=1, old after=0, new=1)

  1) test the dependency requirement the README hands a consumer …
     test/beam_mcp/readme_claims_test.exs:80
     the README no longer contains the sentence this test pins:
       {:beam_mcp, "~> 0.2"}
  8 tests, 1 failure
```

And the guard is not specific to that one string — altering any pinned sentence fails the same
way:

```
MUT 2: "**neither result is decorated**" -> "**neither result is adorned**"
  the README no longer contains the sentence this test pins:  **neither result is decorated**
  8 tests, 1 failure
```

All eight `claims()` fragments are present in the README today — I extracted them from the test
source and checked each against `README.md` rather than reading them off:

```
  8 claims() calls found
  PRESENT  '{:beam_mcp, "~> 0.2"}'
  PRESENT  '| `ping` | removed from the revision, refused | answered |'
  PRESENT  '| result envelope | `resultType` and `_meta` `serverInfo` |'
  PRESENT  '**neither result is decorated**'
  PRESENT  'every method it implements is served bare, `tools/call`'
  PRESENT  'Nothing in this package refuses a request because'
  PRESENT  '`tools/call`, `shutdown`, `exit` at both eras'
  PRESENT  '**`2024-11-05` is not supported**'
```

The design is right, and the part I want to name is the half that is easy to leave out: the test
asserts the *quote is still there*, so a claim that moves without its test fails, and a test
guarding a deleted claim fails too. That is what stops the file rotting into decoration. Test
count checks out as well — 39 before, eight tests in the new file, `47 tests, 0 failures`.

---

## Finding 1 — non-blocking. The `initialized?` check has a hole, and it is shaped like the thing it looks for

`test/beam_mcp/readme_claims_test.exs:160-178` pins the SCR-255 property by scanning `lib/**/*.ex`
for lines containing `initialized?` and rejecting any line that also contains `initialized?:` or
`| initialized?`, on the grounds that those are declarations rather than reads.

A pattern match is a read and contains `initialized?:`. So the filter drops the most idiomatic
Elixir form of exactly the enforcement the test exists to detect.

**Demonstrated — and I proved the mutant applied by effect before scoring it**, because my first
attempt did not:

```
MUT 3 (first attempt): clause inserted before `shutdown`, i.e. AFTER the real tools/call clause.
  Compiled clean. 8 tests, 0 failures.
  -> unreachable. DISCARDED, not scored. This is CLAUDE.md §4b's "mutations never applied and
     scored as survivors", and I walked into it from the same direction you did on mutant B.

MUT 3 (correct): clause inserted BEFORE the real tools/call clause.
  $ mix run <effect probe>
    bare tools/call -> {"error":{"code":-32002,"message":"Session not initialized"},…}   <- applied
  $ mix test test/beam_mcp/readme_claims_test.exs
    1) …:139 every method is served bare, tools/call included, and tools/call reaches dispatch
    2) …:182 tools/call and shutdown are served under either declared revision
    8 tests, 2 failures

  structural test (:160, "nothing in lib/ reads the initialized? flag") fired?  0  -- it did not
```

So: **the security property is genuinely pinned** — two behavioural tests fail the moment
enforcement appears, which is the outcome that matters and is why this is not blocking. What is
wrong is narrower and still worth fixing: the one test whose *stated* job is "nothing reads the
flag" reports a pass while a clause is pattern-matching on it and refusing requests. Under
`CONVENTIONS.md:20-37` that is a probe that cannot see the violation it is aimed at.

The fix follows this project's own idiom — derive, then compare to an expected set rather than
filtering by substring:

```elixir
assert Enum.sort(lines_containing("initialized?")) == Enum.sort(@known_declarations)
```

Then a new line of *any* form fails, including a pattern match, and the four known declarations
are visible in the test instead of implied by a `reject`.

## Finding 2 — non-blocking. "Eight files" is eleven, and three of them were added by this commit

`FINDINGS.md:437`:

> `$ grep -rn '0\.1\.2' --include='*.md' . | grep -v _build | grep -v deps/`
>
> returns hits in **eight** files.

Run in this tree:

```
      9 slices/001b-ping-guard/FINDINGS.md
      8 slices/001b-ping-guard/PLAN.md
      7 slices/001b-ping-guard/logs/round7.r1.md      <- added this round
      7 slices/001b-ping-guard/logs/round1.r2.md
      3 slices/001b-ping-guard/logs/round7.r2.md      <- added this round
      1 slices/001b-ping-guard/REVIEW.md
      1 slices/001b-ping-guard/logs/round4.r2.md
      1 slices/001b-ping-guard/logs/round2.r2.md
      1 slices/001b-ping-guard/logs/round2.r1.md
      1 slices/001b-ping-guard/logs/round1.r1.md
      1 CONVENTIONS.md                                <- added this round
  -> 11 distinct files
```

"Eight" was right for the round-7 tree. It went stale inside the commit that typed it, because the
same commit tracked the two round-7 lane reports and wrote a `CONVENTIONS.md` section quoting the
string. Seventh instance of the family, and the sharp part is *how* it was fixed: the paragraph
says "the fix is to read the command's output rather than to summarise it from memory" — the
output was read, and then the number was typed into prose, where a typed number is exactly as
perishable as before. Round 6 found the durable remedy for this and it was available here:
**delete the count and let the command speak**, e.g. "returns hits in the files that command
lists, all of them archives or historical record", with no integer to go stale.

I checked the `CONVENTIONS.md` hit rather than assuming it: it is `the \`0.1.2\` that changed`, a
correct historical reference inside the derivation of the new rule. It stays. None of the eleven
is a live artifact stating a wrong current fact.

---

## The tally at 27/27 — honest, and I checked it the way the tally cannot

You asked whether the balance is honest or arranged. My round-6 finding 2 was that the tally
compares integers, not sets, so a balance can be arranged by a double count. I ran the set
comparison the tally does not:

```
  enumerated: 27 lines, 27 unique
  classified: 27 lines, 27 unique
  duplicates among classified (an ARRANGED balance shows here):  none
  enumerated but NOT classified:  none
  classified but NOT enumerated:  none
  => SETS ARE EQUAL: the 27/27 balance is HONEST, not arranged
```

Thirteen verdicts plus fourteen lane reports, every name distinct, both set differences empty.

**And the tally firing on you is the most useful thing in this round.** It caught a file its own
author had added and not classified — my round-5 regression, committed again one round after the
guard was built — and the file turned out to be a filtered capture, instance #4. Your record says
the honest reading is not "the guard worked", and I agree with the correction: the guard's value
is that it *fails* rather than reports. A column of `RAW` verdicts would have been clean and
silent, because the one file that mattered was not in the column at all.

## The two mutation re-takes

Both are raw — seed banner, progress dots, complete failure bodies with `code:` and `stacktrace:`,
`Finished in`, count — and both reproduce against my own independent runs of the same mutations:

```
                     failing test lines (order-independent)        final line
  mine (mut A)       :80                                           8 tests, 1 failure
  mutation-readme-a  :80                                           8 tests, 1 failure
  mine (mut B)       :139 :151 :182 :191                           8 tests, 2 failures
  mutation-readme-b  :139 :151 :182 :191                           8 tests, 2 failures
```

The only diffs are the compile prologue, dot-run placement, and ExUnit numbering the two failures
by finish order — mine reported `:139` first, the archive `:182` first. Same set, same counts.

Your note on mutant B is right and I would put it more strongly: `old remaining: 1` was not a weak
signal, it was **no signal**, because the replacement embeds the original. The count answered a
question nobody was asking. What proves a mutant applied is that the tree behaves differently, and
I had to apply that rule to myself this round — my first enforcement clause compiled, changed
nothing, and produced `0 failures`, which I would have been entitled to write down as "the
structural test caught nothing and neither did the behavioural one". It was discarded and re-run
with the effect proved first. SCR-259 from the other side, twice in one round, by both of us.

## Verified

- **Sweep**: byte-identical to the tracked `archive-sweep.txt` from a copy created empty and
  verified empty with **no `_build` at all**; `exit=0`; zero `DIFFERS`; both new mutation logs
  classified. The script delta is only the `mutation-readme` block, and its `[ -f "$f" ] || continue`
  is fail-safe: a missing file stays enumerated by `git ls-files`, so the tally fails rather than
  the file vanishing.
- **Round-7 findings 2 and 3** fixed by derivation: the moved-file set now comes from
  `git diff --stat`, names `full-suite.txt` and `green-negotiation.txt`, says the version reason
  does not explain them, and records `README.md` as the live artifact that should have moved.
  (Finding 2 above is the knock-on for the other half.)
- **`CONVENTIONS.md`** carries the new standing rule, and it quotes my `Version.match?` table and
  my framing accurately — including the part that matters most, that nothing was broken and the
  defect was directional. A rule derived from a finding is worth more than the finding.
- **Gate**: six `pass` lines, `20 commentable files` (19 + the new test file), `gate exit=0`.
  Full suite `47 tests, 0 failures`, and 39 + 8 = 47 checks out.
- **`logs/round7.r1.md`** as tracked is byte-identical to the bytes I wrote.

---

## Summary

The base moved and every claim about the move re-derives. `lib/` is untouched; the only executable
change is a new test file, and it is a good one — the `claims()` design gives it teeth, I proved
that by putting my own round-7 defect back and watching the suite go red, and all eight pinned
sentences are present in the README today. The two mutation re-takes are raw and reproduce against
my own runs. The 27/27 tally is honest by set comparison, not just by arithmetic.

Nothing blocking. Two items: the `initialized?` structural check drops a pattern-match read, which
is the idiomatic form of the enforcement it hunts — the property stays pinned by the two
behavioural tests beside it, which I confirmed by mutation, so this is about that one test's
verdict rather than about coverage. And "eight files" is eleven, stale inside the commit that
typed it, where round 6 had already found the durable answer: delete the number.

VERDICT: approve
