<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# HANDOFF — beam_mcp, slice 003 (the live 002 findings), release 0.3.1

Tag and publish are owner steps — never `mix hex.publish`, never push a tag.

**How many review rounds this had is recorded below, in the round table of
`slices/003-release-0-3-1/FINDINGS.md`, and not summarised here.** The first draft of this line
said "two rounds complete" while one was, which is a claim of review that had not happened
sitting in the file a reader trusts for exactly that. The table is written as each round closes;
it is the answer.

## State

- Branch `slice/003-release-0-3-1`, rebased onto `main` at `955d501` after slice 004 merged.
  The rebase moved this branch onto a **stricter gate**: 004 widened the REUSE population from a
  four-extension glob to every tracked file, so this slice's own `.md` records are now policed by
  it and pass.
- **No head hash is written here.** The last handoff named `bdb032f` and it was stale within the
  hour, because a hash written into the file it describes cannot include the commit that writes
  it. The commits are listed below by subject; `git log main..slice/003-release-0-3-1` is the
  authority for their hashes.
- Gate green **on the rebased tree**: format, compile, test, credo, optional deps, docs,
  reuse (231 tracked; 58 in scope, 56 headered + 2 sidecar), licence files. Every step line reads
  `pass`, read as lines and not as an exit code. `logs/gate-rebased.txt`; the pre-rebase run is
  `logs/gate-release.txt` and is kept rather than overwritten.
- **162 tests, 0 failures.** Was 160 before slice 006's two anchors, 158 before the fifth defect, 146 when this slice's second half
  began, 138 at the 0.2.x-era handoff.
- Version **`0.3.1`**, unreleased. **`0.3.0` is published on Hex and tagged `v0.3.0`**, and its
  changelog section is dated and not amended.

## What this slice produced

    (a)  an x-mcp-header on a non-primitive property is the host's fault
    (b)  colliding x-mcp-header names are refused, not silently collapsed
    (c)  a malformed host spec keeps the request id, like a raising host catalog
    (d)  a refusal issued before the body read ends the connection and says so
         round 1: three claims about correct code corrected
         0.3.1 — the release commit: mix.exs, CHANGELOG, README, this file
    (e)  a header value that is not valid UTF-8 is refused, not reflected

(a) to (d) were review findings from slice 002, filed rather than fixed at the time. **(e) was
found by this slice's own round 3 and reported without a fix**; the owner called it in — it is
unauthenticated and attacker-reachable, and tagging without it would ship a known 500 path. Its
anchor on `fault_response/4`'s answer branch was **replaced, not deleted**, exactly as round 3's
test comment required.

Each of the five carries
its own red, demonstrated and archived before its fix, and each anchor is scored by mutation on
the tree that ships.

**A new instrument.** `test/beam_mcp/transport/http_bandit_test.exs` drives the transport against
a real Bandit listener on a real socket with real pipelining. Everything else in the suite goes
through `Plug.Test`, whose `read_body/2` is a `:binary.part` of an in-memory binary — it can
neither block nor fail, and there is no connection for a refusal to leave in a bad state. Two
gaps in slice 002's findings were recorded there as not closable without this. It closes one.

**The pattern held again, one level up.** Round 1's two lanes found **no defect in `lib/`**. All
three blocking findings were claims *about* the code that were false: a justification nobody had
measured, an off-by-one in a derived population, and a published derivation command that returned
nothing on the tree it described. Slice 002 recorded the failure moving one level away from the
code each round — defect, then test anchor, then record. It started at the record here.

## Owner decisions still open

1. **`SECURITY.md`'s supported-versions table.** Unchanged by this slice; check it still says
   what you want for a `0.3.x` patch before the tag.
2. **Date the `[0.3.1]` heading** at tag time. It reads `unreleased`, correctly, until then.
3. **The README version pin does not move, and that was measured rather than assumed.**
   `~> 0.3.0` admits `0.3.1` and still excludes `0.4.0`, so the recommendation is already right
   for a patch. `slices/003-release-0-3-1/logs/measure-version-requirement.txt`:

        requirement   0.1.0    0.2.0    0.3.0    0.3.1    0.4.0    1.0.0
        ~> 0.3.0      false    false    true     true     false    false

   `readme_claims_test.exs` derives the next break from `mix.exs` and refutes it, so this stays
   true by test rather than by memory.

## Known gaps, recorded rather than fixed

Every one of these is in `slices/003-release-0-3-1/FINDINGS.md` with its measurement.

- **`fault_response/4`'s re-raise branch is still unpinned**, and the never-re-raise mutant still
  survives. The owner scoped it out of this slice. The instrument it needs now exists.
- **`check_annotations/2` inside `host_call/1` is unpinned and is a recorded survivor.** The
  mutant leaving it outside survives, because reaching a difference needs a `properties` map key
  with no `String.Chars` implementation *and* a type offence or a name collision. No JSON-derived
  schema can produce that. Recorded with the argument rather than pinned by a contrived test.
- **`read_body_bounded/1`'s `{:error, reason}` `400` has no test**, and now carries the new close
  behaviour untested with it. `Plug.Test` cannot produce the shape and Bandit raises instead of
  returning it.
- **A bodyless non-POST now costs a connection.** `GET /mcp` leaves nothing unread, so closing on
  it buys nothing. Deciding per request would reintroduce the per-site reasoning that left six of
  seven sites unfixed; the trade is taken deliberately.
- **A correction to slice 002's record.** Lane s3 measured `second-request-answered=False` for a
  pre-read refusal. On bandit 1.12.5 that does not reproduce at ordinary body sizes — the adapter
  drains and the second request IS answered. The defect is real above the drain cap and in what
  the server is made to read below it; the symptom named for it was not this adapter's.
- **`authorize/1` cannot read the body**, so body-signature auth is structurally impossible and
  fails as a hang. Documented in the README; the post-read hook is deferred.
- **`readme_claims_test.exs` does not deliver what `CONVENTIONS.md` asks.** The rule says every
  behavioural README claim is pinned; the file pins every claim *listed in it*, and nothing
  derives the claim set. Stated in that file's moduledoc, unchanged by this slice.
- `ToolCatalog.fetch/2`'s `@spec` honesty, and the unpinned both-eras `ttlMs`/`cacheScope`
  emission, are on the board.

## To release 0.3.1

1. Merge the PR to `main` (the ruleset requires two green checks).
2. Date the `[0.3.1]` heading.
3. `mix hex.publish`, then tag `v0.3.1` signed — or tag first and publish immediately after.
   The GitHub ruleset targets **branches, not tags**, so a tag push is unprotected.
