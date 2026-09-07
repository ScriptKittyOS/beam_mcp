<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Slice 003 — findings

Written as each round closes, not at the end. `CONVENTIONS.md`: *"A report owed only at the end
is a report a crash deletes."* The session doing this work was killed mid-run once already.

## The closing rule, stated before round 1 opened

**Three rounds maximum. Two lanes per round. Every lane writes both artefacts, every round.**

    slices/003-release-0-3-1/logs/round<N>.<lane>.md      the verdict
    slices/003-release-0-3-1/logs/round<N>.<lane>.tree    the tree the verdict was read against

Neither is optional and neither is ceremony. Measured gaps in shipped slices: `001b-ping-guard`
has 16 verdicts and **zero** tree pins, so no verdict there is bound to the tree it was written
against; `002-streamable-http` round 4 has three tree pins and **one** verdict. This slice does
not add a third instance.

**A round closes when both its lanes have written both artefacts and every blocking finding is
either fixed with a red demonstrated before the fix, or recorded below under "Open, recorded
rather than fixed" with the argument for why.** A survivor recorded as a survivor is correct; a
test asserting an implementation detail so a table can read all-killed is worse than the
survivor, because it looks like evidence.

**The slice ships when a round closes with no blocking finding outstanding, and no later than
round 3.** If a blocking finding is still open after round 3, the affected change does not ship
and the reason is written here rather than argued away.

### How the lanes were actually run, stated plainly

This slice was worked by a single agent instructed not to spawn further agents. **The two lanes
per round are therefore two independent passes by the same reader, not two readers.** They are
scoped differently and each runs against a pinned tree and writes its own verdict, but they do
not have the independence the separate lanes in slice 002 had. Saying so is the point: a record
should not imply an independence it does not have. Where a lane's independence would have
mattered, the verdict says so.

    lane a   correctness and anchors. Scores every anchor by mutation rather than reading a
             test and agreeing with it. Reads lib/ and test/ as a pair.
    lane b   the shipped artefact as a consumer meets it, and the record. README, CHANGELOG,
             mix.exs, HANDOFF, the slice's own logs and counts. Re-derives every population
             claim with the command the record says produced it.

## Round-by-round

| round | lane | tree | blocking | filed | verdict |
|---|---|---|---|---|---|
| 1 | a | `1d27f1a` | 1 (A1) | 2 (A2, A3) | changes required, made |
| 1 | b | `1d27f1a` | 2 (B1, B2) | 1 (B3) | changes required, made |

### Round 1 — three record defects in code that behaves correctly

Both lanes read commit `b821818`, tree `1d27f1a`. **No lane found a defect in what the code
does.** All three blocking findings were claims *about* the code that were false:

**A1 — a justification nobody had measured.** `tool_annotations/2`'s comment said
`check_annotations/2` moved inside `host_call/1` because a non-string `properties` key raises in
`Enum.join/2` there. The mutant that leaves it outside SURVIVES (`mutation-c-Mc2.txt`, 156 tests,
0 failures), and the reason it survives shows the sentence is wrong: the path is only reached on
a type offence or a name collision, so such a key alone raises nothing. The move is kept and is
now described as defensive, with the survivor recorded below.

**B1 — an off-by-one in the population, in the commit that fixed a population defect.** Three
places said six pre-read refusal sites and then named a seventh. Re-derived, there are seven:
`read_body_bounded/1`'s 413 and 400 are both in the set, and the 413 is the one that already
closed. The behaviour was right in all seven; the sentence was wrong in three files.

**B2 — the published derivation stopped working on the tree it describes.** The quoted
`grep '<- read_body_bounded'` returns nothing after the fix, because the fix moved that call out
of the `with` clause list. A derivation that cannot see the boundary it defines is not one. It is
replaced by `grep -n 'defp before_body' -A 10`, which shows the steps and the read, re-run and
quoted in `round1.b.md`.

**The pattern slice 002 recorded — the failure moving one level away from the code each round —
held on the first round of this slice.** The code was sound. Every blocker was a record.

Gate at round 1 close: `logs/gate-round1.txt`, all eight step lines `pass`, `GATE_EXIT=0`.

## Open, recorded rather than fixed

**1. `check_annotations/2` inside `host_call/1` is unpinned, and deliberately so.** `Mc2` --
the spec read and schema walk inside, the validity check outside -- survives at 156 tests, 0
failures (`logs/mutation-c-Mc2.txt`). Reaching a difference needs a `properties` map whose KEY
has no `String.Chars` implementation *and* a type offence or a name collision, so that
`annotation_detail/1` interpolates it. No JSON-derived schema can produce that. Pinning it would
mean a test constructing a schema no host can write, which is an implementation detail wearing a
test's clothes. Recorded as a survivor with the argument, per `CONVENTIONS.md`.

**2. `fault_response/4`'s re-raise branch is still unpinned.** `M2never` survives at 147 tests,
0 failures (`logs/mutation-c-M2never.txt`), unchanged by this slice and scoped out of it by the
owner. Detecting it needs a non-500 `:plug_status` exception from code that is not the host's --
the adapter's read path alone. This slice stands up the Bandit-backed instrument that could
close it (`test/beam_mcp/transport/http_bandit_test.exs`) and does not use it for this, because
the scope says not to. That is the whole remaining work: an existing instrument, an excluded
task.

**3. Invalid UTF-8 in `MCP-Protocol-Version` turns a caller's own 400 into a 500.** Measured:
the bytes are echoed into the refusal's `data.requested`, so `Jason.encode!` raises
`Jason.EncodeError` inside `send_json/3` in `handle/2`'s `else` -- outside every inner rescue --
and the caller gets a 500 with an error-level stacktrace in the host's log per request, on a path
`authorize/1` may leave unauthenticated. `Plug.Exception.status(%Jason.EncodeError{}) == 500`, so
it lands on `fault_response/4`'s answer branch and is answered inside the envelope; nothing leaks
and nothing crashes. Not fixed here: one commit does one thing, and this is a third defect in a
slice scoped to two.

It is also, today, **the only path in the suite that reaches `fault_response/4`'s answer
branch**, which is why the anchor for that branch sits on it. The test says so in terms and says
that when the reflection is fixed the anchor must be replaced rather than deleted. Recording a
defect as a defect while using it as an anchor is uncomfortable and is the honest option: the
alternative was leaving the branch unpinned, which is what `M2always` -- a bodyless 500 -- would
then have walked through.

**4. `read_body_bounded/1`'s `{:error, reason}` 400 has no test.** Derived:
`grep -rn "Could not read request body" test/ lib/` returns one hit, the source line.
Pre-existing, and now carrying the new close behaviour untested with it. `Plug.Test`'s
`read_body/2` is a `:binary.part` and cannot return `{:error, _}`; Bandit raises rather than
returning it for the malformed framings tried here.

**5. A bodyless non-POST now costs a connection.** `GET /mcp` leaves nothing unread, so closing
on it buys nothing and costs a handshake. Deciding per request whether the body was consumed
would reintroduce the per-site reasoning that left six of seven sites unfixed. The trade is
uniformity at the split against one connection per rejected non-POST, and it is taken
deliberately.

**6. A correction to slice 002's record, appended here rather than made there.** Lane s3
recorded `second-request-answered=False` for a pre-read refusal. On bandit 1.12.5 /
thousand_island 1.5.0 that does not reproduce at ordinary body sizes: `ensure_completed/1`
drains the body and the second pipelined request IS answered
(`logs/probe-d-bandit-drain.txt`, three sizes to 1 MB, all `responses=2`). The defect is real --
above the adapter's 8_000_000-byte drain cap the connection is dropped with nothing said, and
below it the server reads megabytes for a caller it refused -- but the symptom named for it is
not the one this adapter shows.
