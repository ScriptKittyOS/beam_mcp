<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Slice 006 — FINDINGS

**Issue:** SCR-289. Every count below is quoted from a command's output; the command and its
archive are named beside it.

## The closing rule, written before round 1 opens

Two lanes, three rounds maximum.

- **Lane `m` — the mechanism.** Is the diagnosis right, is the replacement a replacement rather
  than a retune, and can the new read logic still fail when the behaviour it pins is removed?
- **Lane `h` — the record and the instrument.** Do the archives say what was measured, is
  `tools/mutate.sh` re-runnable by someone who has only this repository, and does anything here
  claim more than it measured?

A round closes when both lanes have recorded a verdict with `tools/signoff.sh record`, and both
`logs/round<N>.<lane>.md` and `logs/round<N>.<lane>.tree` exist for that round. The slice closes
when the highest round is `approve` from both lanes on the current review tree — that is,
`tools/signoff.sh verify slices/006-harness-honesty` exits 0. If round 3 closes with any
`changes-required` outstanding, the slice **stops and reports** rather than opening a round 4.

A lane that could not spawn its own subagents says so in its own verdict rather than letting
"two lanes" imply an independence it does not have.

## The red, and it is a rate

### In CI, on commits containing no code

Two push-event runs failed on the same assertion, on two different commits, neither of which
contains a line of Elixir:

    run 34174975336  PR #15  seed 70815  160 tests, 1 failure
    run 34175931068  PR #17  seed 11394  160 tests, 1 failure
      1) test a live listener: what a refusal does to the connection
         a refusal over the adapter's drain cap now announces the close it always did
         code: assert String.contains?(bytes, "HTTP/1.1 403")

Both commits' `pull_request` runs of the **same commit** passed. The two events run the identical
job (`.github/workflows/gate.yml` has one `gate` job and no event conditionals), so one commit
produced two answers. Two failures in the fifteen most recent push runs; `main` has three green
runs in that window and is **not immune, merely unhit**. Both runs are left red as standing
evidence and were not re-run.

### On the development machine, before any change

    mix test --max-cases  8, 100 consecutive runs, 32 idle cores   2 of 100 exited non-zero
    mix test --max-cases 64, 100 consecutive runs, 32 idle cores   1 of 100 exited non-zero

`logs/red-rate-mc8-idle.txt` and `logs/red-rate-mc64-idle.txt`. All three failures are that same
test, and each prints what the local rate makes visible and the CI transcript did not — **the
argument**:

         code: assert String.contains?(bytes, "HTTP/1.1 403")
         arguments:
             # 1
             ""

`bytes` is **empty**. Not short, not partial: empty. The whole suite finished in 3.5 s, so the
10_000 ms first-byte window was never reached either.

**The local rate is 2% and CI's is 2 in 15. The disagreement is reported rather than smoothed:**
this machine has 32 cores and CI has far fewer, and everything measured below says the defect is
governed by whether the client process is scheduled in time. A rate that rises when CPU is scarce
is consistent with that; it is not evidence of two different defects, and it is not evidence of
one either. What closes the question is the CI run at the end of this slice, not this paragraph.

## The PLAN's hypothesis was wrong, and here is what is actually wrong

The PLAN said `drain/2` terminates on wall-clock silence, so under load it returns a **partial**
buffer and reports `:open`. **Refuted.** The failing read returns an **empty** buffer and reports
`:closed`, and it never takes a timeout branch at all — which is also why slice 003's repair,
splitting one 700 ms window into `10_000 + 700`, reduced the rate and left the mechanism. You
cannot retune your way out of a branch you are not in.

### Where the bytes go

`logs/probe-drain-mechanism.txt` — the 9 MB refusal, 40 runs per variant, reporting
`{bytes received, recv reason, send result, saw the 403?}`:

    A  send everything, then read (what the file did)   29x {297, :closed, :ok, true}
                                                        11x {0, :closed, :ok, false}
    B  A, plus show_econnreset: true                    21x {297, :closed, ...}
                                                        11x {297, :econnreset, ...}
                                                         8x {0, :econnreset, :ok, false}
    C  passive recv concurrent with the write           40x {297, :closed, :ok, true}
    D  C, plus show_econnreset: true                    25x {297, :econnreset, ...}
                                                        15x {297, :closed, ...}

The server refuses on the headers, writes a 297-byte 403, and closes with ~9 MB still unread, so
Linux aborts the connection with an RST rather than a FIN. **The response is lost, not late.**
`show_econnreset: true` renames the error and does not save the data.

### Which side loses it

`logs/probe-loss-site.txt` puts a message-sending `authorize` callback in the plug so that "the
server never answered" is distinguishable from "the answer never arrived", and runs 60 exchanges
under 32 busy loops:

    57x  {297, :econnreset, ..., authorize ran: true}
     3x  {0,   :econnreset, ..., authorize ran: true}

**The server decided and wrote its refusal 60 times out of 60.** Three of those refusals never
reached the client. `logs/probe-write-shape.txt` rules the write shape out as the governor: on the
same loaded machine, 120 runs in one 9 MB send lost 0 and 120 runs in 64 KB chunks lost 5.

So there are two distinct faults wearing one symptom, and they need different fixes:

1. **A verdict reported over a buffer that was never read.** `drain/2` answered `{acc, :closed}`
   and `{acc, :open}` over whatever `acc` held, including nothing. This is the whole defect and it
   is entirely on this side of the wire.
2. **A response segment destroyed in transit** by the RST the server's own close emits. No read
   logic can recover it. Roughly 5% of exchanges at worst under deliberate CPU starvation.

## The fix

`test/beam_mcp/transport/http_bandit_test.exs` only. `lib/` is untouched — verified by
`git status` on every archived run, and by `tools/mutate.sh`, which restores its target from an
EXIT trap.

1. **The read terminates on the protocol.** `collect/3` reads until `expect` **complete** HTTP
   responses have been parsed — status line, headers, and the `content-length` bytes that follow.
   Every response this adapter sends declares a length, so completeness is decidable from the
   bytes. A timeout is no longer a verdict: it raises.
2. **`active: true`, and the write in its own process.** A passive socket keeps received bytes
   inside the port, and a failing `gen_tcp:send` destroys the port — so a reader not yet
   *scheduled* to call `recv` loses them, which is exactly what CPU starvation produces. Measured:
   the passive-but-concurrent shape still lost 6 of 40 loaded suites
   (`logs/probe-rate-mc8-load32-passive.txt`). In active mode the driver posts `{:tcp, ...}` into
   this process's mailbox without this process running, and a message in a mailbox cannot be taken
   back by a port dying.
3. **`:open` versus `:closed` survives, and is asked in the right order.** `settle/2` is only
   entered once the responses are already complete. TCP delivers a FIN in order behind the bytes
   that preceded it, so this window is not racing the response; it is racing only the server's own
   close syscall. `:open` is the absence of an event and cannot be decided any other way over a
   socket — that is stated in the file rather than hidden, and what it can no longer do is report
   a verdict over an empty or short buffer.
4. **An exchange that produced no measurement is repeated, not reported.** The predicate is
   protocol-determined — *the connection ended with fewer than `expect` complete responses* — and
   it is decided before any assertion runs. Reporting a destroyed exchange as `{"", :closed}` was
   the old defect; reporting it as a failed `assert bytes =~ "HTTP/1.1 403"` is the same lie with
   the sign flipped, a sentence about the server for bytes the server did send. Bounded at 5
   attempts (5% at its worst leaves 3e-7), announced on stderr, and it raises if every attempt is
   destroyed.

**The rejected alternatives stayed rejected.** No timing constant was raised: `@hold_ms` is still
700, and `@read_ms` 10_000 is now a backstop that raises rather than a window that answers. Nothing
runs at `--max-cases 1` and nothing is isolated with a settle interval.

## The two new anchors, and they move

`drain/2` was pinned by nothing: it was the instrument, so no test could see it lie. Two tests at
the bottom of the file now drive it from a raw scripted listener, and both were mutated to prove
they carry information (`logs/mutation-harness-anchors.txt`):

    H1  the read terminates on silence again (`collect` hands straight to `settle`)
        162 tests, 2 failures   TEST_EXIT=2
    H2  a destroyed exchange is reported as a verdict again ({:destroyed,...} -> {acc, :closed})
        162 tests, 1 failure    TEST_EXIT=2
    unmutated                    162 tests, 0 failures

The suite is **162 tests** where the record's tables say 160: these two are the difference.

## The direction that matters: a survivor must still read as a survivor

This is the criterion the PLAN calls load-bearing, because the error ADDS a failure and a table
that reads all-killed is a table nobody investigates.

`tools/mutate.sh score`, 4 passes per mutant, under 32 busy loops on 32 cores, first with the
harness as it was and then with the harness as it ships.

**Before** (`logs/red-mutation-under-load.txt`), against slice 003's recorded table:

    M2never  0 failures (SURVIVOR)  read  1 | 1 | 1 | 0     <- FALSE KILLED, 3 of 4 passes
    Mc2      0 failures (SURVIVOR)  read  0 | 0 | 0 | 0
    M13rev   1                      read  1 | 2 | 2 | 2
    M2always 1                      read  1 | 2 | 2 | 1
    Mc3      2                      read  2 | 2 | 3 | 3
    Md1      9                      read  9 | 9 | 9 | 9
    Md2      2                      read  2 | 3 | 3 | 3
    Me1      1                      read  1 | 1 | 1 | 1
    Mr1      4                      read  4 | 4 | 5 | 5
    Mr2      3                      read  3 | 4 | 3 | 3

Round 3 of slice 003 recorded a false KILLED and could not reproduce it on demand. **It is
reproducible on demand**: 16 of 40 scored suites read one failure more than the mutant deserves,
and the row it corrupted is a recorded survivor.

**After** (`logs/green-mutation-under-load.txt`), same command, same 4 passes, same 32 busy loops,
on the harness as it ships:

    M13rev   1 | 1 | 1 | 1        Md1      9 | 9 | 9 | 9
    M2always 1 | 1 | 1 | 1        Md2      2 | 2 | 2 | 2
    M2never  0 | 0 | 0 | 0        Me1      1 | 1 | 1 | 1
    Mc2      0 | 0 | 0 | 0        Mr1      4 | 4 | 4 | 4
    Mc3      2 | 2 | 2 | 2        Mr2      3 | 3 | 3 | 3

**Forty scored suites, zero variance, every row equal to slice 003's recorded table.** Both
survivors survive. The log also names the failing TEST in every row — an addition to the
instrument, because "160 tests, 1 failure" reads identically whether the failure is the mutant's
or the harness's, and that ambiguity is what let round 3's false KILLED be written down. `Md1`,
the mutant that removes the very behaviour this file pins, still kills seven of the nine live
listener tests, so the read logic has not been made unable to fail.

## The rate after the fix

    mix test --max-cases  8, 100 consecutive runs, idle           0 of 100    (was 2 of 100)
    mix test --max-cases 64, 100 consecutive runs, idle           0 of 100    (was 1 of 100)
    mix test --max-cases  8,  40 consecutive runs, 32 busy loops  0 of  40    (was 6 of 40 on
                                                                  the passive-socket draft, and
                                                                  3 of 40 before the repeat)

`logs/green-rate-mc8-idle.txt`, `logs/green-rate-mc64-idle.txt`, `logs/green-rate-mc8-load32.txt`.
The two intermediate drafts are kept as `logs/probe-rate-mc8-load32-passive.txt` and
`logs/probe-rate-mc8-load32-active.txt`, because each is the measurement that refused the fix
before it.

**N is derived, not chosen.** At the measured red of 2% a 100-run green has a 13% chance of being
luck; the loaded profile is what supplies the power. The loaded run also shows the repeat working
rather than merely present: counting the stderr announcements per suite,

    36 suites with 4 repeats     <- the four the "server that never answers" anchor causes
     3 suites with 5
     1 suite  with 7

so **six exchanges in forty loaded suites produced no measurement and were repeated**, and none of
them became a failure. That is the same ~5% loss `logs/probe-loss-site.txt` measured, caught and
named instead of asserted about.

## What is NOT done here

- Slice 003's table is not re-scored, and its records are not rewritten. The false KILLED it
  recorded is now reproducible, which strengthens that record rather than replacing it.
- PR #15's and PR #17's red push runs were not re-run.
- `lib/` is untouched. No part of this fix needed shipping code.
