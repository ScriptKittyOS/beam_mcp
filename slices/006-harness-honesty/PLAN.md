<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Slice 006 — harness honesty: a gate run must be a measurement, not a sample

**Issue:** SCR-289. **Written before any code.**

**006 is the number; it runs FIRST.** Slice 005 (tool identity) already started — its PLAN is
committed and PR #15 is open — so 005 is taken. Under the numbering rule, a number is identity
assigned when a slice starts, and **order is not number**: this slice is 006 and it goes ahead of
005. That separation is the rule working rather than an exception to it.

**Why it goes first.** A test defect reaching CI means every *"gate green, every step line reading
pass"* in this repository is currently a **sample rather than a measurement**. That sentence is
the evidence behind every slice record here. Nothing that depends on mutation scoring — 005's
acceptance criterion 2 does — can be recorded honestly until it is true again.

---

## 0. What is actually wrong, read from the code rather than the issue

`test/beam_mcp/transport/http_bandit_test.exs`, `drain/2`:

    @first_byte_ms 10_000
    @quiet_ms 700

    defp drain(sock, acc) do
      timeout = if acc == "", do: @first_byte_ms, else: @quiet_ms
      case :gen_tcp.recv(sock, 0, timeout) do
        {:ok, data} -> drain(sock, acc <> data)
        {:error, :timeout} -> {acc, :open}
        {:error, :closed} -> {acc, :closed}
      end
    end

**The read terminates on a wall-clock silence, not on a protocol event.** Once any byte has
arrived, a gap longer than 700 ms is interpreted as "the server is done and holding the
connection". Under load a gap that long is ordinary, so the function returns a **partial buffer**
and reports `:open`, and every assertion downstream is then made against bytes that had not
finished arriving.

This is already a documented repair of a previous instance of itself. The comment above those two
attributes records that a **single** 700 ms window made the 9 MB case flaky, and that it presented
as *"a SURVIVING mutant scoring as KILLED"*. The repair split one window into two and made the
first generous. **It reduced the rate and did not remove the mechanism**, which is why the same
test failed again in CI at `max_cases: 8`.

That is the finding to keep in front of the work: the previous fix was a threshold change, and a
threshold change cannot fix a race. This slice replaces the mechanism.

## 1. The three observations this slice must account for

| when | where | how it presented |
|---|---|---|
| slice 003 round 3 | dev machine, `max_cases: 64` | `Mc2`, a **survivor**, scored as **KILLED** |
| slice 003 re-score | dev machine, 40 back-to-back suites | `M13rev` read 2 (record 1), `Mr2` read 4 (record 3) |
| PR #15 push run | **GitHub Actions, `max_cases: 8`** | `test FAIL (exit 2)`, `assert String.contains?(bytes, "HTTP/1.1 403")`, on a commit containing **no code** |

One mechanism, three load profiles, and the error always has the same direction: **it adds a
failure.** A flake that removes a failure makes a table pessimistic and someone investigates. One
that adds a failure makes a table read all-killed, and nobody does.

## 2. Red first, and the red is a RATE

An intermittent defect has no single transcript. The red is a measured rate, captured whole:

1. **N consecutive runs of the Bandit test file**, on the development machine, recording *k*
   spurious failures and naming the failing test each time.
2. **The same at `--max-cases 8`**, because that is CI's profile and where the consequential
   failure was caught. A rate measured only at 64 has not been measured where it failed.
3. **N is derived from the observed rate, not chosen.** One failure in ~20 CI runs and two in 40
   local suites are the starting estimates; the PLAN's first act is to measure the rate properly
   so that "no failures after the fix" is a claim with power behind it rather than a short run
   that got lucky.

## 3. The fix: remove the wall-clock window, do not retune it

**Requirement, not a candidate.** `drain/2` must terminate on something the protocol determines,
not on elapsed silence. The shape to settle in this PLAN before code:

- read until the socket closes, or until the expected number of **complete** HTTP responses has
  been parsed — `Content-Length` is present on every response this suite asserts against, so
  completeness is decidable from the bytes;
- keep a timeout **only** as a stuck-test backstop, long enough that reaching it is a failure of
  the test rather than a verdict of it, and assert on reaching it rather than returning a partial
  buffer silently;
- `:open` versus `:closed` must remain distinguishable, since three tests assert on it. Deciding
  how, without a silence window, is the design question this slice answers.

**The rejected alternatives are named so they are not revisited:** raising `@quiet_ms`, running the
mutation set with `--max-cases 1`, and running mutants in isolation with a settle interval. Each
lowers the rate on one profile and leaves the mechanism. The repository has already bought the
threshold fix once.

## 4. Acceptance criterion, as a measurement

1. **The rate is measured before the fix** (§2), at both `max_cases` profiles, captured whole.
2. **After the fix, zero spurious failures over a run derived from that rate** — the population
   comes from the measurement, not from a round number.
3. **A known SURVIVOR still reports as a survivor under the conditions that produced the false
   kill.** `M2never` or `Mc2` from slice 003, scored under sustained back-to-back load. This is the
   criterion that matters: the direction of the error is what makes it dangerous, and a fix that is
   only shown not to *add* failures on a quiet machine has not been tested where it lied.
4. **Demonstrated at CI's `max_cases: 8`**, in CI, not only locally.
5. **The mutation harness is committed**, under `tools/`. Slice 003's record cites `$S/mut.sh
   <name>`, a scratchpad path no future reader can resolve. A scoring instrument that cannot be
   re-run is not evidence — the same rule that governs archives: written by a command that can
   fetch it, or it does not exist. The nine mutant scripts and the pristine-file discipline move
   with it.
6. **Gate green, and green repeatedly.** A single green run is precisely the claim this slice
   exists to stop trusting, so the gate is run enough times to have caught the measured rate.

## 5. What this slice does NOT do

- **It does not re-score slice 003.** That table is the isolated runs, its two survivors are
  recorded as survivors with their arguments, and its record already carries the instability.
- **It does not re-run PR #15's red check.** That failure is standing evidence and stays red until
  this slice lands. A green re-run would destroy the only artefact showing a no-code commit failing.
- It does not touch `lib/`. If the fix requires a change to shipping code, that is a finding and
  the slice stops and reports rather than widening.

## 6. Process

Two lanes, three rounds maximum, closing rule written before round 1 opens. Every round writes both
a verdict and a tree pin per lane, bound with `tools/signoff.sh`.

**This brief supersedes the earlier "do not spawn further subagents": the lanes may spawn.** A lane
that cannot says so in its own verdict rather than letting "two lanes" imply independence it does
not have.

**One caution specific to this slice.** Its own acceptance criteria are measured with the
instrument it is repairing. A run that says the fix worked is subject to the same doubt as a run
that said a survivor was killed — so criterion 3 is the load-bearing one, because it checks the
instrument against a value already known by other means rather than against itself.
