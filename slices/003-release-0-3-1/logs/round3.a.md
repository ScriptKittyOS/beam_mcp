# Round 3, lane a — the mutation table on the tree that actually ships

Tree read: `c504d36db97a22bc745c157c7d2e68e3d98479a4` (commit `11e0b7a`). Pin: `round3.a.tree`.
Scope: every mutant this slice has scored, re-run on the final tree; the Bandit harness itself.

**Verdict: changes required (one), and it is made. It is the most important finding of the three
rounds.**

## Blocking

**C1. A flake made a SURVIVOR score as KILLED.**

Slice 002 round 7's blocker was a mutation table headed "on the tree that ships" whose scoring
run was a smaller tree. Every mutant in this slice was first scored in the round that produced
it, at 147, 156 or 158 tests, so the same defect was available here. Re-running the whole set on
the final tree is the answer to it, and doing that is what surfaced this:

    Mc2   check_annotations/2 left outside host_call/1
          round 1, at 156 tests:            SURVIVED   156 tests, 0 failures
          first re-score, at 158 tests:     "KILLED"   158 tests, 1 failure

The failure was not the mutant. It was
`http_bandit_test.exs`'s 9 MB case, failing on an empty receive buffer:

    1) test ... a refusal over the adapter's drain cap now announces the close it always did
       code: assert String.contains?(bytes, "HTTP/1.1 403")
       # 1
       ""

`drain/2` used one 700 ms window for every read. Under the load of the scoring loop itself the
9 MB upload had not finished inside it, so the harness gave up before the server had said
anything and the test failed for a reason that had nothing to do with the code under test.

**Why this is the sharpest finding in the slice.** `CONVENTIONS.md` says a survivor recorded as
a survivor is correct, and that a test written so the table reads all-killed is worse than the
survivor because it looks like evidence. A flaky harness produces that same false table without
anyone writing a dishonest test — the table simply reads better than the truth, in the direction
nobody checks. Had the second pass not been run, this slice's record would have claimed a
pinned check that is not pinned.

**Fixed** in the harness, not by deleting the test: `drain/2` now waits generously
(`@first_byte_ms 10_000`) for the FIRST byte, which is bounded by how long the client takes to
finish writing, and only then uses the short quiet window (`@quiet_ms 700`) that distinguishes
"the server is holding this connection" from "the server is done". The control tests still pay
only the quiet window, because they receive immediately.

**Demonstrated stable rather than declared fixed.** Ten consecutive runs of the Bandit file,
`logs/flake-check-bandit.txt`, `9 tests, 0 failures` ten times. And the full mutation set run
**twice** end to end, `logs/mutation-round3.txt`.

## The table, on the tree that ships, run twice

    mutant     applied  pass 1                       pass 2
    M13rev     1        158 tests, 1 failure         158 tests, 1 failure
    M2always   1        158 tests, 1 failure         158 tests, 1 failure
    M2never    1        158 tests, 0 failures        158 tests, 0 failures
    Mc2        1        158 tests, 0 failures        158 tests, 0 failures
    Mc3        1        158 tests, 2 failures        158 tests, 2 failures
    Md1        1        158 tests, 9 failures        158 tests, 9 failures
    Md2        1        158 tests, 2 failures        158 tests, 2 failures
    Mr1        1        158 tests, 4 failures        158 tests, 4 failures
    Mr2        1        158 tests, 3 failures        158 tests, 3 failures

`applied=1` is the count of `+++` lines in that mutant's diff against the pristine file, which is
in its own log — so every mutant is shown applied rather than reported applied. `M13rev` and
`Md1` remove what they orphan (`tool_annotations/2` and `close_after/1`), because
`--warnings-as-errors` would otherwise fail the build before the suite ran and the table would
record a kill no test made.

**Two survivors, both recorded as survivors with the argument, in `FINDINGS.md`:** `M2never`
(`fault_response/4`'s re-raise branch, scoped out by the owner) and `Mc2` (defensive rather than
defect-driven, and unreachable from any JSON-derived schema).

**Md1 and Md2 both gained a failure** against their round-1 scores (8→9 and 1→2). The extra in
each is the release commit's new README-claim test, which is the rule working: a claim added to
the README in one commit is pinned by a test that dies with the behaviour.

## Read and accepted

- The 9 MB case is **not** RST-prone in the way it first appeared. Measured directly, ten runs
  at each size, `logs/probe-d-large-body-reset.txt`: `pad=0` and `pad=9000000` both give
  `10x response=403 recv_ended=:closed send=:ok`. The client gets its refusal and then the
  close. The earlier empty buffer was the harness's window, not a reset.
