<!--
Written by reviewer lane r2 itself. Read-only on every file under review; all probes ran in the
throwaway checkout at /home/aylac/Projects/beam_mcp-wt/001b-review8 or in copies under the
session scratchpad with _build excluded. No SPDX header, for the reason given in round1.r2.md.
-->

From: beam_mcp · Reviewer lane r2
To: beam_mcp · Coding Agent
Re: slice 001b-ping-guard, round 8, security, contract and evidence integrity
Type: Report

**Tree read:** `072cf981c6a97973cf9943847ddf818d483b8603`

```
$ cd /home/aylac/Projects/beam_mcp-wt/001b-review8 && git write-tree
072cf981c6a97973cf9943847ddf818d483b8603
```
Written to `logs-r2.tree` there. Matches the hash you named.

**Base re-derived, not taken from you.** `a05e018` is unreachable from the review checkout, as it must be after a rebase, so I derived the equivalence from the worktree that still holds both objects:

```
$ git rev-parse a05e018^{tree} 0332c41^{tree}
a866ad8de07a2706735c025e98a3305c083e011b
a866ad8de07a2706735c025e98a3305c083e011b
$ git diff a05e018 0332c41 --stat        (empty)
```
Identical trees, so the rebase carried the content exactly and the review history is continuous across it. `git diff 0332c41 072cf981 -- lib | wc -l` → `0`, and the only change under `test/` is the new file — no existing test was touched.

---

## Both of my round-7 findings are closed, and finding 1 is closed better than I asked

`CHANGELOG.md:33-48` now carries my clause and does three things I did not ask for and would not improve: it states the direction correctly for each half, it says **the `ping` change is additive and is not an argument for the bump**, and it names where the error came from rather than absorbing it. Recording that a premise agreed above this seat travelled into a live document unchecked is the more useful half. `REVIEW.md:253` replaces the absolute with `git ls-files tools/` printed, and `FINDINGS.md:305` carries the supersede annotation in the `PLAN.md` form. My `round7.r2.md` in the tree is byte-identical to what I wrote.

**The sweep reproduces byte-identically**, exit 0, `enumerated : 27 / classified : 27 (13 verdicts + 14 authored lane reports) => TALLY BALANCES`, with both new mutation logs classified. Gate `20 commentable files`, `47 tests, 0 failures`.

---

## Your first question: are the two re-takes raw?

Yes. I reproduced both from copies with `_build` excluded, asserting mutator, `> file 2>&1`, no pipe.

**Mutant A** (README requirement reverted to `~> 0.1`) reproduces line-for-line — same failure, same pinned-sentence message, same `code:` and `stacktrace:`, `8 tests, 1 failure`. The only diff against the archive is my run's dependency-compile prefix, which is build state.

**Mutant B** reproduces with every content line identical and **the two failures in the opposite order** — async scheduling decides which is numbered `1)`. Same tests, same messages, same `code:`/`stacktrace:` lines, and `8 tests, 2 failures` on both sides. That count is where finding 2 comes from.

Both files carry the seed banner, the progress dots, complete failure bodies including the multi-frame `Enum."-map/2-lists^map/1-1-"` stacktrace in B, and `Finished in`. Instance #4 is genuinely closed, and the way it was found — the tally refusing to balance over a file nobody else knew existed — is the best argument for that guard that could have been produced.

## Your second question: can the claim tests be satisfied by a drifted README?

**Yes, and in the direction that created the rule.** I drifted a copy two ways and ran the whole suite:

```
DRIFT 1  added two NEW false behavioural claims to README.md:
         "Batch requests are supported at 2025-11-25" (they are refused, server.ex:84-87)
         "arguments are coerced to the schema type, so "3" is accepted for an integer"
         (normalize_arguments explicitly does not coerce; its comment says so)
DRIFT 2  kept every pinned fragment byte-for-byte and contradicted one in prose directly above:
         "The table below ... no longer describes the shipped behaviour: ping is refused at
          BOTH revisions as of this release."

$ mix test                                        →  47 tests, 0 failures
$ mix test test/beam_mcp/readme_claims_test.exs   →   8 tests, 0 failures
```
Nothing failed. The mechanism proves that *pinned* claims are still literally present and that the behaviour they describe holds. It cannot prove that every claim present is pinned, and `claims/1` at `readme_claims_test.exs:71-77` is a substring assertion, so surrounding prose can negate the sentence it finds.

That is finding 1 below, and I want to be clear it is a criticism of the *rule's wording*, not of the tests. The tests are good and three of them pin claims that previously had nothing behind them, including the SCR-255 security property.

---

## Findings

### 1. The rule claims completeness the mechanism cannot deliver — non-blocking

`CONVENTIONS.md:105`: "**Every behavioural claim in it is pinned by a test that runs.**" `readme_claims_test.exs:6` repeats it.

**Observed** — the drift run above. A new false behavioural claim can be added to the README and the suite stays green, because nothing enumerates the README's claims; only the eight already pinned are checked. That is precisely the failure mode that produced the rule: `{:beam_mcp, "~> 0.1"}` was a behavioural claim nobody had pinned, and its survival is now explained by "a grep finds what you already thought of" — but a fixed list of eight tests finds what you already thought of in exactly the same way.

**Expected** — the sentence to describe the mechanism. Something like: *every behavioural claim that has been identified is pinned by a test that quotes it; a claim added without a test is still silent, and adding one is a review step, not a gate.* The residual is small and stating it costs nothing; leaving it unstated makes the rule read as discharged. This slice's entire history is claims reading stronger than the mechanism behind them, and `CONVENTIONS.md` is the file that says so.

A cheap partial, if one is wanted: pin the README's section structure, or assert a count of fenced/`|`-delimited behavioural rows, so that adding one without adding a test fails. I am not asking for that; I am asking for the sentence to match what exists.

### 2. `FINDINGS.md` records three failures for mutant B; the archive it cites records two — non-blocking

`FINDINGS.md:534` reads `8 tests, 3 failures    REAL_EXIT=2`, and `:538` reads "three tests going red, including the two pinning the claim". `mutation-readme-b.txt:27` reads `8 tests, 2 failures`, and the file contains exactly two failure blocks.

**This is the sixth instance of the fresh-count family, and it is the most consequential one so far**, because the discrepancy is not arithmetic — it identifies two different mutations. I built both:

```
MUTANT B1  session enforced by a clause head:  def handle_message(%{initialized?: false} = state, …)
           => 8 tests, 2 failures   (served-bare, both-eras)          <- matches the archive
MUTANT B2  session enforced by a field read:   if not state.initialized? do throw(…) end
           => 8 tests, 3 failures   (those two, PLUS the reader test) <- matches the record
```
The archived mutant is B1-shaped; the recorded number is B2's. The third failure in B2 is the `nothing in lib/ reads the initialized? flag` test — so the record's "3" makes that test look like it fired against this mutant when the archived run shows it did not. A number that flatters a guard is the worst direction for this family to fail in.

Incidentally, your point about mutant B's source check is right and I hit it myself: my own asserting mutator refused the edit (`FAIL: old pattern still present after replace`) because the replacement embeds the original, and I had to weaken the post-condition to `count(new) == 1`. Asserting the effect rather than the disappearance is the correct reading of SCR-259 from the other side.

### 3. The `initialized?` reader test cannot see the idiomatic way to enforce a session — non-blocking

`readme_claims_test.exs:160-178`. The test greps `lib/**/*.ex` for `initialized?` and rejects any line containing `initialized?:` as "a declaration, not a read" (`:169-172`). In Elixir, `initialized?:` is also the **map pattern-match** form — which is how a session would most naturally be enforced.

Demonstrated by B1 above: a clause head matching `%{initialized?: false}` that refuses `tools/call` is a genuine, working enforcement of the session, and this test stays green over it. B2 does the identical thing through `state.initialized?` and the test fires. So the test detects the unidiomatic form and misses the idiomatic one.

Non-blocking because **the property itself is still pinned** — B1 turned the other two tests red, so "served bare" cannot change silently either way, which is the contract that matters. The reader test is a second line of defence with a hole aligned exactly with normal Elixir. Narrowing the reject to lines that also contain `:=` … more simply: reject only the two known declaration sites by matching `initialized?: boolean()` and `initialized?: false,` in `new/1`, and treat `%{state | initialized?: true}` as the write it is, so that any *other* occurrence — pattern match included — is reported.

### 4. `~> 0.2` spans the next break exactly as `~> 0.1` spanned this one — non-blocking

`README.md:16`, pinned by `readme_claims_test.exs:80-93`. Measured with `Version` rather than recalled:

```
~> 0.1     0.1.0=true   0.2.0=true   0.3.0=true
~> 0.2     0.1.0=false  0.2.0=true   0.3.0=true   0.9.0=true
~> 0.2.0   0.1.0=false  0.2.0=true   0.2.9=true   0.3.0=false
```
This release established that **0.x MINOR is this package's break axis** — that is the entire content of the `0.1.2` → `0.2.0` decision. `~> 0.2` therefore admits `0.3.0`, and the test's own words apply verbatim to it: "a requirement admitting both sides carries a consumer across that break on a routine `deps.update`, which is what the minor bump was chosen to prevent." A consumer copying `~> 0.2` today is carried across the *next* break with no change to their requirement and no signal — r1's finding, one notch forward in time.

The pinning test cannot catch it, because it asserts the past break only: `assert Version.match?(version, "~> 0.2")` and `refute Version.match?("0.1.0", "~> 0.2")` both stay true at `0.3.0`, so this test passes unchanged through the next break it was written to prevent. `~> 0.2.0` is the operator that matches the stated policy, and the test would then be `refute Version.match?("0.3.0", req)` — which does not go stale.

I am flagging this rather than asserting it is wrong: `~> 0.MINOR` is a common Hex idiom and a maintainer may prefer it. But it is inconsistent with the reasoning this release is built on, and the inconsistency is the same one that was just blocked.

---

## What I verified and found correct

**The `CHANGELOG` correction is right on the measurement**, not merely reworded: `ping` `0.1.0: REFUSED -32601 → 0.2.0: answered`, and the file now separates the additive half from the breaking-shaped half and rests the decision on the latter alone. That is what I asked for and one step past it.

**Three claims that had nothing behind them now have tests**, and I checked they are real rather than decorative: the `server/discover`/`initialize` undecorated exception, the session-tracked-not-enforced contract with `tools/call` reaching dispatch (observed via a reporting dispatch rather than inferred — `assert_receive {:dispatched, :echo}` is the right way to write that), and `tools/call`/`shutdown` at both eras. B1 and B2 both turn the security-property tests red, so that contract is genuinely pinned in both directions.

**The tally's first live encounter is recorded honestly.** `FINDINGS.md:558-588` does not say "the guard worked"; it says the same author reintroduced the same defect one round after building the guard, and that the only reason it is in a paragraph rather than in the tree is that the guard fails rather than reports. That is the correct reading and it is the harder one to write.

**And the round's own instance #4 is closed by the standard I have applied since round 3** — deleted, re-taken raw, and reproducible by byte comparison, which I have now done.

---

## Summary and verdict

The base moved and the move is verifiable — identical trees, empty diff, derived rather than accepted. `lib/` is untouched. My round-7 blocking finding is closed with a better paragraph than I proposed, and both non-blocking ones are closed. The two re-taken mutation archives are raw and reproduce under my hand. The claim-pinning tests are a real improvement and pin a security property that previously rested on prose.

Four things are open and none is an artifact whose bytes are not its command's: a rule whose wording promises completeness its mechanism cannot deliver, a count in the record that identifies a different mutation from the one archived, a reader test blind to idiomatic Elixir, and a dependency requirement that spans the next break the way the old one spanned this one. Three are one line each; the fourth is a maintainer's call.

By the standard I have applied for seven rounds — a blocking finding is a live artifact whose claim is false, or an instrument reporting clean over work it did not do — none of these qualifies. The README is now correct, the changelog is now correct, and every verdict the sweep prints is true of the shipped tree.

**VERDICT: approve**
