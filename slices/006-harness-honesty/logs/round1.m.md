<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Slice 006, round 1, lane m — the mechanism

**Tree:** `e2f8a0898362319a3aeb44a5a89e090d546858ff`
**Commit:** `90e4e99f8bda256fc7c5a526e4fc2b3bd8ef6d25` (branch `slice/006-harness-honesty`)

**Scope.** The mechanism only: is the diagnosis right, is the replacement a replacement rather
than a retune, is the repeat honest, can the new read logic still fail when what it pins is
removed, is any existing assertion made vacuous, and is `lib/` untouched. Not the prose — lane
`h` has the record. Everything below names its command and its exit code; every count is quoted
from output.

---

# **Verdict: changes required**

Two blocking findings, both cheap to clear. The diagnosis is right, the replacement is a genuine
replacement of the failing branch, and the mutation table reproduces — but the **repeat is not
anchored at all**, and I turned an 80%-broken server into a clean pass through it.

---

## What I ran

| # | command | result |
|---|---|---|
| 1 | `git diff a02e560 --stat -- lib/` | **no output**, exit 0 |
| 2 | `mix test` (unmutated) | `162 tests, 0 failures` `TEST_EXIT=0` |
| 3 | `tools/mutate.sh check` | 10/10 `applied`, `restored: lib/beam_mcp/transport/http.ex is the file you started with` |
| 4 | `PASSES=1 tools/mutate.sh score Mc2 Mc3 M2never Md1` | see §3 |
| 5 | H3 — a mutation the archive does not use | `162 tests, 3 failures` `TEST_EXIT=2` |
| 6 | H4 — `@attempts 5` -> `2` | `11 tests, 0 failures` `TEST_EXIT=0` |
| 7 | H5 — `@attempts 5` -> `1` | `162 tests, 0 failures` `TEST_EXIT=0` |
| 8 | temporary probe test (§4) | `12 tests, 0 failures` `TEST_EXIT=0` |

`git status --porcelain` after every mutation and after the score run listed **only** this round's
four untracked `logs/round1.*` files — no tracked file modified. The pristine test file was taken
before the first mutation and restored by `cp` each time.

---

## 1. The diagnosis is right, and the PLAN's hypothesis really is refuted

The old code (`git show 6050eff~1:test/beam_mcp/transport/http_bandit_test.exs`) is what FINDINGS
says it is:

    {:error, :timeout} -> {acc, :open}
    {:error, :closed}  -> {acc, :closed}

with `@first_byte_ms 10_000` guarding the first byte. The PLAN predicted a **partial** buffer via
the `:timeout` limb. Checked against the archives:

- `grep -c timeout logs/red-rate-mc8-idle.txt logs/red-rate-mc64-idle.txt` -> **`0` and `0`**. The
  timeout limb is not in either red transcript. It cannot have produced those failures.
- `grep -n -A4 'arguments:' logs/red-rate-mc8-idle.txt` -> two hits (lines 6787, 24102), each
  `# 1` followed by `""`. Two failures, both on an **empty** buffer, matching "2 of 100".
- `logs/probe-drain-mechanism.txt:225` -> `11x  {0, :closed, :ok, false}`. Zero bytes read, reason
  `:closed`, server's 403 gone.

Empty buffer, `:closed` limb, no timeout. **The refutation holds and it is properly evidenced.**
This also correctly explains why slice 003's `700 -> 10_000 + 700` split lowered the rate without
removing the mechanism.

## 2. The replacement is a replacement — with one honest exception, disclosed

No timing constant was raised: `@hold_ms` is still `700`, `@read_ms` is still `10_000`, and
`@connect_ms 5_000` is the old inline literal given a name. The two new constants are `@write_ms
15_000` (a join on the writer process; on expiry it falls through to `:ok` and decides nothing)
and `@attempts 5`. `@read_ms` genuinely no longer answers — it `raise`s.

**`settle/2` still answers `:open` on a timeout, so the brief's "no timeout may decide a verdict"
is not literally satisfied.** The stated argument is *sound as far as ordering goes*: `settle/2`
is unreachable until `complete_responses(acc) >= expect`, TCP delivers FIN behind the bytes that
preceded it, and the `inet` driver posts `{:tcp_closed, _}` / `{:tcp_error, _, _}` into a FIFO
mailbox after the `{:tcp, _, data}` it already posted. So the 700 ms window cannot cut a response
in half any more, and it cannot verdict an empty buffer.

What it still races is the **server's own `close/1` syscall**, and that gap is unbounded under CPU
starvation. If a server writes its 403 and is then descheduled for >700 ms before closing, the
seven `assert state == :closed` tests read `:open` and fail — the *old* failure direction, at a
much smaller window. So this is **narrowing, not elimination**, and I would not sign a claim that
the class is gone.

It is not a threshold fix wearing a proof, because the fix moved the *branch*, not the number, and
the file says so in its own words ("It is still a window, and it is named as one. `:open` is the
ABSENCE of an event and cannot be decided any other way over a socket"). That is the honest
version and I am not asking for it to change. **Non-blocking**, recorded so nobody later reads
"terminates on the protocol" as covering `:open`.

## 3. The mutation table reproduces, independently

`PASSES=1 tools/mutate.sh score Mc2 Mc3 M2never Md1`, on this tree, quoted from its output:

    Mc2     | 162 tests, 0 failures TEST_EXIT=0
    Mc3     | 162 tests, 2 failures TEST_EXIT=2
    M2never | 162 tests, 0 failures TEST_EXIT=0
    Md1     | 162 tests, 9 failures TEST_EXIT=2

Both recorded survivors (`Mc2`, `M2never`) read as survivors; `Mc3` reads 2 and `Md1` reads 9,
equal to slice 003's table and to `logs/green-mutation-under-load.txt`. `Md1` names 9 failing
tests, 7 of them the live-listener refusal tests, so the read logic has not been made unable to
fail on the behaviour it exists to measure. `git status --porcelain` after the run showed no
tracked modification: `lib/` was restored.

Instrument nit, non-blocking: `score`'s header line prints `dirty=$(git status --porcelain | wc
-l)`, which counted my four untracked log files as `dirty=4`. It cannot distinguish "uncommitted
`lib/` changes" from "untracked files in `slices/`", which is the thing a reader would use it for.

## 4. **BLOCKING — the repeat can launder a genuine server defect, and nothing pins its bound**

This is the finding. Three results, in order.

**(a) `@attempts` is a contained anchor.** `H4`, changing `@attempts 5` to `@attempts 2`:

    mix test test/beam_mcp/transport/http_bandit_test.exs
    11 tests, 0 failures    TEST_EXIT=0

Nothing moved. The reason is visible in the anchor itself — the "server that never answers" test
asserts

    ~r/#{@attempts} exchange\(s\) in a row produced no measurement/

against a message built from the same `@attempts`. The constant is on both sides of the
comparison, so it cannot disagree with itself. This is exactly CONVENTIONS.md's **contained
anchor** shape.

**(b) The whole repeat mechanism can be deleted and the suite stays green.** `H5`, `@attempts 5`
-> `1` (with `attempt < @attempts` false on the first pass, no exchange is ever repeated):

    mix test
    162 tests, 0 failures    TEST_EXIT=0

Fault 2's entire fix — the thing `logs/probe-loss-site.txt` was measured to justify and the thing
`@attempts` is derived for ("5% at its worst leaves 5 attempts at 3e-7") — carries **no anchor at
all** on an idle machine. Both new tests pass without it.

**(c) An intermittently silent server is repeated into a pass.** I appended one temporary test: a
`fake_listener` whose handler closes without answering on the first four connections and answers
on the fifth — a server broken 80% of the time. Output:

    http_bandit_test: exchange 1/5 produced no measurement (:closed after 0/1 complete responses, 0 bytes). Repeating on a fresh connection.
    ... 2/5 ... 3/5 ... 4/5 ...
    TEMP-PROBE: {"HTTP/1.1 200 OK\r\ncontent-length: 11\r\n\r\n{\"ok\":true}", :closed} after 5 connections
    12 tests, 0 failures
    TEST_EXIT=0

**A server that fails four connections in five reports a clean pass.** FINDINGS says "A server
that genuinely never answers fails every attempt and raises, so nothing is masked." That sentence
is true only of a *deterministic* silence. The repeat is designed to absorb a ~5% loss and it
cannot tell a 5% loss caused by an RST on the wire from a 5% loss caused by the server, because
the predicate — *the connection ended with fewer than `expect` complete responses* — is identical
in both cases. `logs/probe-loss-site.txt` could separate them only because it instrumented the
plug's `authorize` callback; the shipping harness has no such instrument.

And the one signal that survives is dropped by the scoring instrument:

    grep -c 'produced no measurement' logs/green-mutation-under-load.txt  ->  0
    grep -c 'produced no measurement' logs/green-rate-mc8-load32.txt      ->  166

`mutate.sh`'s `suite()` keeps only the count line and the failed-test names, so a defect absorbed
by the repeat leaves **no trace in any scored run**. (The 166 checks out against FINDINGS'
arithmetic: 40 suites x 4 announcements from the anchor test itself = 160, plus the 6 real ones.)

**What would clear it.** Any one of these, not all three:

1. An anchor that moves when `@attempts` moves — e.g. a listener that stays silent for exactly
   `n` connections then answers, asserting a pass at `n = @attempts - 1` and a raise at
   `n = @attempts`. That pins the bound and, written that way, states in the suite what (c)
   demonstrates: the repeat *is* able to convert an intermittent defect into a pass, up to its
   bound. The anchor must not interpolate `@attempts` into its own expectation.
2. Make the repeat count observable to the scorer — count announcements per suite and fail (or at
   minimum print into the count line `mutate.sh` keeps) above the measured 6-in-40 baseline, so an
   absorbed defect cannot be silent in a mutation table.
3. If neither is wanted, say in FINDINGS what is actually true: the repeat cannot distinguish a
   lost segment from an intermittently silent server, so it absorbs both up to 5 attempts, and the
   only evidence it is not absorbing a real defect is the unchanged mutation table. Replace
   "nothing is masked" — that claim is measurably too strong.

I would take (1) plus (3).

## 5. **BLOCKING (minor) — the anchor evidence quotes counts the archive does not contain**

FINDINGS' "The two new anchors, and they move" reads:

    H1 ... 162 tests, 2 failures   TEST_EXIT=2
    H2 ... 162 tests, 1 failure    TEST_EXIT=2
    unmutated                       162 tests, 0 failures

`grep -n '162\|tests,' logs/mutation-harness-anchors.txt` returns, from the file itself:

    57:11 tests, 2 failures
    105:11 tests, 1 failure
    110:11 tests, 0 failures

The archive ran the **single file** (`mix test test/beam_mcp/transport/http_bandit_test.exs`), so
its totals are 11, not 162. The failure counts (2, 1, 0) and the conclusion are right; the totals
were typed to match the suite figure rather than quoted from the run that is cited as their
evidence. That is the one rule this slice exists to defend — "Counts are quoted from command
output, never typed" — broken inside the slice's own proof, and it is why I am blocking on
something so small.

**What would clear it:** print the file-scoped totals as the archive prints them (`11 tests, ...`)
and name the command that produced them, or re-run the two mutants over the full suite and archive
that instead.

## 6. `expect` does not make the existing assertions vacuous — but it changes how they fail

`settle/2` keeps accumulating (`{:tcp, ^sock, data} -> settle(sock, acc <> data)`), so `responses/1`
still counts everything that arrives inside the hold window and an over-count still fails. Checked
by effect rather than by reading: `H3` — `content_length/1` returning `{:ok, 0}`, so completeness
stops depending on the declared body length, a mutation **the archive does not use** — gave

    162 tests, 3 failures    TEST_EXIT=2
      1) ... an ordinary 200 keeps the connection and answers the pipelined second request
      2) ... a refusal AFTER the body has been read keeps the connection
      3) ... a response split across the hold window is read whole, not cut at it

So the completeness change **is** anchored, by a mutation independent of `H1`/`H2`, and the two
`responses(bytes) == 2` tests move under it too. Neither of the COMPILER KILL or CONTAINED ANCHOR
shapes applies here: the mutant compiles, and the assertion is on an observable byte count.

Worth stating rather than blocking on: with `expect = 2`, the *downward* half of
`assert responses(bytes) == 2` is now guaranteed by construction — a server that answers once
never reaches the assertion, it exhausts `@attempts` and raises. The suite still fails (H3's
failures 1 and 2 are exactly that path), but it fails saying *"5 exchange(s) in a row produced no
measurement ... a server that does not answer"* about a server that answered once. That message is
wrong for that defect, and it costs five connections to produce. Not vacuous; mislabelled.

## 7. `lib/` is untouched

    git diff a02e560 --stat -- lib/     (no output, exit 0)

Confirmed again by `git status --porcelain` after `tools/mutate.sh check` and after the `score`
run, both of which reported the target restored.

---

## What I did not check

- **CI.** PLAN acceptance criterion 4 is "demonstrated at CI's `max_cases: 8`, in CI". I ran
  nothing in CI and read no CI run for this branch. Per CONVENTIONS.md that criterion is
  unverified until a run exists, and nothing in this verdict speaks to it.
- **The rate claims.** I did not re-run 100 suites at either profile, or 40 under 32 busy loops. I
  read `logs/green-rate-*.txt` for the announcement counts only. The 0-of-100 and 0-of-40 numbers
  are taken on the record's word.
- **The other six mutants.** I scored 4 of 10, at `PASSES=1`, on an idle machine — enough to
  confirm the table reproduces and the survivors survive, not enough to speak to variance under
  load.
- The prose, the README, `HANDOFF.md`, and whether `tools/mutate.sh` is re-runnable by someone with
  only this repository beyond the `check`/`score`/`run` paths I used. Lane `h`.
