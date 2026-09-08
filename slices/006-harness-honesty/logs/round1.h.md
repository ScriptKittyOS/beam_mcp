<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Slice 006, round 1 — lane `h`: the record and the instrument

**Tree read:** `e2f8a0898362319a3aeb44a5a89e090d546858ff`
**HEAD at read time:** `90e4e99f8bda256fc7c5a526e4fc2b3bd8ef6d25` — *"Correct the test count this slice
made false, and two paths that resolve nowhere"*.
**Commits read:** `6050eff`, `4a10c0d`, `24370ce`, `90e4e99`.

**Scope.** Not the mechanism (lane `m` has that). Every number in `FINDINGS.md` and in the four
commit messages checked against the archive it cites, with a command; whether `tools/mutate.sh` is
re-runnable by someone holding only this repository; whether the gate's REUSE step can see the new
`tools/` files; whether the archives are whole command output; whether anything claims more than it
measured; and whether PLAN §4 is discharged.

**Verdict: changes required.**

Four blocking findings. None of them is in the fix — the mechanism work stands up to every check I
could make of it from the record's side, and eleven of the fourteen archives reconcile exactly. All
four are in the record, which is where this repository's history says the failure lands.

---

## Blocking

### H-1. The anchor table reports a suite run that never happened

`FINDINGS.md` §"The two new anchors, and they move" prints, citing
`logs/mutation-harness-anchors.txt`:

    H1  ...  162 tests, 2 failures   TEST_EXIT=2
    H2  ...  162 tests, 1 failure    TEST_EXIT=2
    unmutated                        162 tests, 0 failures

The archive it cites says something else. Quoted from the file:

    $ sed -n '17p;57,58p;73p;105,106p;108p;110p' slices/006-harness-honesty/logs/mutation-harness-anchors.txt
    --- H1: mix test test/beam_mcp/transport/http_bandit_test.exs ---
    11 tests, 2 failures
    TEST_EXIT=2
    --- H2: mix test test/beam_mcp/transport/http_bandit_test.exs ---
    11 tests, 1 failure
    TEST_EXIT=2
    restored; unmutated:
    11 tests, 0 failures

The anchors were mutated against **one file, 11 tests**. The table promotes that to **162 tests**,
the whole-suite number, three times. The failure counts (2, 1, 0) and the exits are right; the
population is not. Three counts typed rather than quoted, in the table whose entire job is to show
that the two new anchors carry information — and in a slice whose thesis is that "160 tests, 1
failure" reading identically to something else is how a false record gets written.

The 162-vs-160 arithmetic itself is sound and independently supported (`git show 6050eff -- test/…`
adds exactly 2 `test "` lines and removes 0; `logs/green-rate-mc8-idle.txt` ends `162 tests, 0
failures`). It is the anchor rows that misdescribe their run.

**Clears it:** re-quote the three rows as `11 tests` and name the command
(`mix test test/beam_mcp/transport/http_bandit_test.exs`), or re-run the two mutations over the
whole suite and archive that.

### H-2. The commit that swept unresolvable log paths out of this file left five in it

`90e4e99` fixes two bare `logs/probe-d-bandit-drain*.txt` citations in
`test/beam_mcp/transport/http_bandit_test.exs`, reasoning: *"A citation that cannot be followed is
not a citation."* Both fixed references were slice 003's, written before this slice. Every citation
**this slice added to the same file** was missed:

    $ for p in $(grep -oE '(slices/[A-Za-z0-9./-]+|logs/[A-Za-z0-9./-]+)\.txt' \
        test/beam_mcp/transport/http_bandit_test.exs | sort -u); do
        [ -e "$p" ] && echo "EXISTS $p" || echo "MISSING $p"; done
    MISSING logs/green-mutation-under-load.txt
    MISSING logs/probe-drain-mechanism.txt
    MISSING logs/probe-loss-site.txt
    MISSING logs/probe-rate-mc8-load32-passive.txt
    MISSING logs/probe-write-shape.txt
    EXISTS  slices/003-release-0-3-1/logs/probe-d-bandit-drain-limits.txt
    EXISTS  slices/003-release-0-3-1/logs/probe-d-bandit-drain.txt

Lines 118, 136, 156, 166 and 179. Same file, same class, same sweep, five instances to two — and
the two that were found are the two that pre-dated the slice. This is CONVENTIONS.md's *"a grep
finds what you already thought of"* happening inside the commit that names the class.

**Clears it:** prefix all five with `slices/006-harness-honesty/`, and say in the record how the set
was derived (the `grep -oE … | while read; do [ -e ]` above is a derivation, a re-read of the
moduledoc is not).

### H-3. The CI table — the premise of the whole slice — has no archive

`FINDINGS.md` §"In CI, on commits containing no code":

    run 34174975336  PR #15  seed 70815  160 tests, 1 failure
    run 34175931068  PR #17  seed 11394  160 tests, 1 failure

plus *"Two failures in the fifteen most recent push runs; `main` has three green runs in that
window"*, and *"Both commits' `pull_request` runs of the **same commit** passed."*

Nothing fetched any of it.

    $ grep -rln '34174975336\|34175931068' . | grep -v '^./.git'
    slices/006-harness-honesty/FINDINGS.md
    slices/006-harness-honesty/logs/round1.h.md      # this file

No `logs/ci-*.txt`, no `gh run view` transcript, no command named beside the numbers, and the
paragraph opens the section that the FINDINGS header promises is quoted-with-its-archive. Six
counts, two run ids, two seeds and a claim about the fifteen most recent push runs, all typed. This
is the exact shape CONVENTIONS.md legislates against — *"a verbatim archive is written by a command
that fetches it, or it does not exist"* — applied to the one measurement that establishes the defect
reached CI, which is the sentence PLAN §0 uses to justify running 006 ahead of 005.

The 100-run local rates beside it are archived properly and reconcile exactly (see below), which
makes the gap sharper rather than softer: the numbers that were cheap to fetch were fetched.

**Clears it:** `gh run view <id> --log` and `gh run list` into `logs/`, cited; or, if the runs are
not to be touched, restate the paragraph as an unarchived citation of where the runs live and stop
printing per-run counts as if quoted.

### H-4. PLAN §4 criteria 4 and 6 are neither discharged nor recorded as undischarged

- **Criterion 4** — *"Demonstrated at CI's `max_cases: 8`, **in CI**, not only locally"* — is not
  discharged. FINDINGS gestures at it once (*"what closes the question is the CI run at the end of
  this slice, not this paragraph"*), but that sentence is inside the rate-disagreement argument, and
  the section explicitly titled **"What is NOT done here"** lists three items, none of them this.
  A reader auditing the acceptance criteria against the record finds criterion 4 neither done nor
  declared outstanding.
- **Criterion 6** — *"Gate green, and green repeatedly"* — is discharged in the tree and absent from
  the record. `logs/gate-round1.txt` holds five consecutive `Gate OK. GATE_EXIT=0` runs with every
  step line reading `pass`, and `logs/red-gate-credo-nesting.txt` holds the red that preceded it
  (`credo FAIL (exit 8)`, nesting depth 3 at `http_bandit_test.exs:351`). **These are the only two
  logs in the slice that FINDINGS.md never cites:**

      $ for f in slices/006-harness-honesty/logs/*.txt; do b=$(basename $f);
          grep -q "$b" slices/006-harness-honesty/FINDINGS.md || echo "UNCITED $b"; done
      UNCITED gate-round1.txt
      UNCITED red-gate-credo-nesting.txt

  Two orphan archives and an undischarged criterion are the same defect from two sides.

**Clears it:** a short gate section in FINDINGS citing both logs and quoting the reuse line, and
criterion 4 added to "What is NOT done here" until a CI run exists.

---

## Non-blocking

### h-5. Two logs carry a different run's banner than their filename

    $ head -1 slices/006-harness-honesty/logs/probe-rate-mc8-load32-passive.txt
    == probe-rate-mc8-load32-fixed ==
    $ head -1 slices/006-harness-honesty/logs/probe-rate-mc8-load32-active.txt
    == green-rate-mc8-load32 ==
    $ head -1 slices/006-harness-honesty/logs/green-rate-mc8-load32.txt
    == green-rate-mc8-load32 ==

Two different files claim the banner `green-rate-mc8-load32`, and one of them is a rejected draft:

    $ tail -1 slices/006-harness-honesty/logs/probe-rate-mc8-load32-active.txt
    == green-rate-mc8-load32: 3 run(s) of 40 exited non-zero ==

A reader grepping the archive for the green loaded run finds a log headed "green" that ends in
three failures. The filenames are right and FINDINGS cites them correctly; the bytes inside are a
rename that did not reach the header. Add a correction line to each (appended, per CONVENTIONS,
not rewritten) saying which run it is.

### h-6. Three archives cite an instrument nobody can re-run — the defect this slice moved `mut.sh` for

    $ git grep -n '/tmp/claude' -- slices/006-harness-honesty/
    logs/mutation-harness-anchors.txt:6:  --- /tmp/claude-…/scratchpad/006/fixed_bandit_test.exs
    logs/mutation-harness-anchors.txt:62: --- /tmp/claude-…/scratchpad/006/fixed_bandit_test.exs
    logs/probe-loss-site.txt:3:  $ env N=60 MIX_ENV=test mix run /tmp/claude-…/scratchpad/006/loss_site.exs
    logs/probe-write-shape.txt:3: $ env N=120 MIX_ENV=test mix run /tmp/claude-…/scratchpad/006/write_shape.exs

`4a10c0d`'s own argument: *"`$S/mut.sh <name>` where `$S` is a scratchpad directory on one machine.
Nobody reading that record can re-run it, which makes the table a claim rather than a measurement."*
`logs/probe-loss-site.txt` is the archive behind *"the server decided and wrote its refusal 60 times
out of 60"* and the ~5% loss that `@attempts 5` is derived from — load-bearing, and its script is
gone with the session.

The slice already contains the fix: `logs/probe-drain-mechanism.txt` opens with
`---- the probe script, verbatim ----` and embeds the whole thing. Do the same for the other two,
and for the anchor mutations name the tracked file rather than the scratchpad copy.

### h-7. "Rules the write shape out" is not what that archive says

FINDINGS: *"`logs/probe-write-shape.txt` rules the write shape out as the governor: on the same
loaded machine, 120 runs in one 9 MB send lost 0 and 120 runs in 64 KB chunks lost 5."* Both numbers
are exactly right —

    $ grep -nE '^== |MISSING in' slices/006-harness-honesty/logs/probe-write-shape.txt
    246:== one_send: 120 runs of the 9 MB refusal, active-mode client ==
    249:   response MISSING in 0/120
    491:== chunked: 120 runs of the 9 MB refusal, active-mode client ==
    495:   response MISSING in 5/120

— and the conclusion drawn from them is the opposite of what they show. 0/120 against 5/120 is the
write shape mattering, not the write shape being ruled out. What the probe supports is narrower:
*loss is not confined to chunked writes at a rate that explains the suite*, or something the data
actually carries. The same paragraph in `6050eff`'s message reads *"The write shape does not govern
it either"*, so the overstatement is in two places.

Related and smaller: the comment at `http_bandit_test.exs:154` says `active: true` *"took the loss
from 11/40 to 3/60"*. 11/40 is variant A of `probe-drain-mechanism.txt`, whose header records no
background load; 3/60 is `probe-loss-site.txt` under 32 busy loops. The like-for-like pair does
exist (6/40 passive-loaded vs 3/60 active-loaded) and is quoted correctly two lines above; the
11/40→3/60 sentence crosses load profiles.

### h-8. `logs/gate-round1.txt` is headed "on the tree that ships" and is two commits behind it

    $ head -4 slices/006-harness-honesty/logs/gate-round1.txt
    == the gate, 5 times, on the tree that ships ==
    date: 2026-09-08T02:37:06Z
    HEAD: a02e5603e6a26ff91af775a0b4cd1d88943c707b
    staged, so tools/ and the mutants are in git ls-files and therefore in the REUSE step's population

`a02e560` is the slice's **base**; the runs measured staged work. `24370ce` and `90e4e99` landed
afterwards, and `90e4e99` edited `test/beam_mcp/transport/http_bandit_test.exs`. `90e4e99`'s message
quotes `Gate OK.  GATE_EXIT=0` with no archive at all. The repository already has a commit named
*"re-score on the tree that ships"*; this is the same gap one step later. (I re-ran the gate myself
on the current tree — see below — and the reuse line is `pass` on it once my probe is restored, so
this is a record gap and not a broken gate.)

### h-9. `mutate.sh`'s restore claim is absolute, and there is no lock

The header says *"an interrupted run cannot leave a mutated file behind."* Measured, three
invocations of `./tools/mutate.sh run Md1` interrupted once the target's sha256 had changed:

    SIG=TERM  mutated_before_signal=yes  wait_rc=0    restored=YES  git status -- lib/: ''
    SIG=INT   mutated_before_signal=yes  wait_rc=0    restored=YES  git status -- lib/: ''
    SIG=KILL  mutated_before_signal=yes  wait_rc=137  restored=NO   git status -- lib/: ' M lib/beam_mcp/transport/http.ex'

The trap holds for `INT` and `TERM`, which is what it traps. `KILL` — and a crash, and a power cut —
leaves the mutant on disk. (I restored it with `git checkout -- lib/beam_mcp/transport/http.ex`;
proof of restore below.) Say "an interrupted run" or say "a run that is not `SIGKILL`ed", not
"cannot".

Second, from reading `start()`/`restore()`: the pristine is a copy of **whatever is on disk when the
invocation starts**, with no lock. Two invocations in one worktree, B starting while A has a mutant
applied, gives B a mutated pristine; if A exits first, B's EXIT trap writes the mutant back and
prints `restored: … is the file you started with`, which is true and misleading. This is not
hypothetical here: lane `m` was running `mutate.sh` in this same worktree during my read, and I
observed `lib/beam_mcp/transport/http.ex` mutated between two of my own commands. A lockfile, or a
refusal when `git status --porcelain -- "$TARGET"` is non-empty at `start`, closes it.

---

## What I ran, and what reconciled

Every count below is from the command shown; `EXIT` is the command's exit code.

**Rate archives — all four reconcile exactly.**

    $ grep -o 'RUN_EXIT=[0-9]*' <log> | sort | uniq -c   /   grep -c '^---- run '
    red-rate-mc8-idle              100 runs   98 x 0,  2 x 2     FINDINGS: 2 of 100   OK
    red-rate-mc64-idle             100 runs   99 x 0,  1 x 2     FINDINGS: 1 of 100   OK
    green-rate-mc8-idle            100 runs  100 x 0             FINDINGS: 0 of 100   OK
    green-rate-mc64-idle           100 runs  100 x 0             FINDINGS: 0 of 100   OK
    green-rate-mc8-load32           40 runs   40 x 0             FINDINGS: 0 of 40    OK
    probe-rate-mc8-load32-passive   40 runs   34 x 0,  6 x 2     FINDINGS: 6 of 40    OK
    probe-rate-mc8-load32-active    40 runs   37 x 0,  3 x 2     FINDINGS: 3 of 40    OK

**The repeat distribution, which is the claim I most expected to be typed, is exact.**

    $ awk '/^---- run /{if(s)print c; s=1; c=0} /produced no measurement/{c++} END{if(s)print c}' \
        logs/green-rate-mc8-load32.txt | sort -n | uniq -c
         36 4
          3 5
          1 7
    $ grep -c 'produced no measurement' logs/green-rate-mc8-load32.txt
    166

FINDINGS' 36/3/1 table is right, and its *"six exchanges in forty loaded suites produced no
measurement and were repeated"* is 166 − (40 × 4) = 6, from the log. EXIT=0.

**Both mutation tables reconcile row by row** against `logs/red-mutation-under-load.txt` and
`logs/green-mutation-under-load.txt` (`M2never 1|1|1|0`, `Mc2 0|0|0|0`, `M13rev 1|2|2|2`,
`M2always 1|2|2|1`, `Mc3 2|2|3|3`, `Md1 9|9|9|9`, `Md2 2|3|3|3`, `Me1 1|1|1|1`, `Mr1 4|4|5|5`,
`Mr2 3|4|3|3` before; every row constant after). I recomputed the headline claim rather than
trusting it: summing, per mutant, the passes reading above slice 003's recorded value gives
3+2+3+0+2+0+3+0+2+1 = **16 of 40**, which is what FINDINGS and `24370ce` both say. The "after" rows
equal slice 003's recorded table at `FINDINGS.md:165-173` of `slices/003-release-0-3-1` for the nine
mutants it lists, and `Me1`'s 1 matches `slices/003-release-0-3-1/logs/mutation-rebased.txt:31`.

**`Md1` kills seven of nine.** The green log lists 7 `HTTPBanditTest` failures under `Md1`; the
describe block has 9 tests:

    $ awk '/describe "a live listener/{f=1} f&&/^  describe /&&!/a live listener/{f=0} f&&/^    test "/{c++} END{print c}' \
        test/beam_mcp/transport/http_bandit_test.exs
    9

**The probe tallies** in `probe-drain-mechanism.txt` (A 29/11, B 21/11/8, C 40, D 25/15) and
`probe-loss-site.txt` (57x/3x of 60) match FINDINGS and `6050eff` exactly, including the abbreviated
form in the commit message. `probe-drain-mechanism.txt` embeds its script verbatim and ends
`PROBE_DONE / PROBE_EXIT=0`; all fourteen archives end in a terminator line and none shows a
truncation or an editing seam.

**162 vs 160.**

    $ git show 6050eff -- test/beam_mcp/transport/http_bandit_test.exs | grep -cE '^\+ *test "'
    2
    $ ... | grep -cE '^\- *test "'
    0
    $ grep -n '162' HANDOFF.md
    30:- **162 tests, 0 failures.** Was 160 before slice 006's two anchors, …

Two tests added, none removed; HANDOFF corrected. The claim is true. Only the anchor table's
rendering of it (H-1) is wrong.

**Slice 003 was not rewritten.**

    $ git diff a02e560 --stat -- slices/003-release-0-3-1
    (no output)
    $ git diff a02e560 --name-only -- slices/003-release-0-3-1 | wc -l
    0
    EXIT=0

**The rate disagreement (2 in 100 local vs 2 in 15 in CI) is reported honestly** and nothing
downstream quietly folds them into one defect: the FINDINGS paragraph says *"it is not evidence of
two different defects, and it is not evidence of one either"*, `24370ce` repeats it, and no count
anywhere in the slice is derived from combining the two. `@attempts 5` is derived from the **local**
loss measurement (`5% at its worst leaves 3e-7`), not from CI. The one thing missing is the archive
for the CI half — which is H-3, and it is a missing archive rather than a smoothed number.

**The instrument, re-run from this repository only.**

    $ ./tools/mutate.sh list                     EXIT=0   (10 mutants)
    $ ./tools/mutate.sh check                    EXIT=0
      M13rev applied (11 changed line(s)) … Mr2 applied (2 changed line(s))
      restored: lib/beam_mcp/transport/http.ex is the file you started with
    $ sha256sum lib/beam_mcp/transport/http.ex   before and after
      d7795a126a484ad8b9aa79541686fd0857a6ab773e666fcca0fa170551dda4f2   (identical)
    $ ./tools/mutate.sh run Mr2                  163 tests, 3 failures  TEST_EXIT=2

All ten mutants apply and restore. `Mr2`'s 3 failures independently reproduce slice 003's recorded
row on a machine that is not the one that wrote the log — which is the point of committing the
harness, and it works. (163 rather than 162 because lane `m`'s uncommitted `TEMP-PROBE` test was in
the worktree at that moment; it has since been removed by lane `m` and the suite is 162 again.)
`git status --porcelain` after each shows no `lib/` entry. No absolute path, `$S`, or scratchpad
reference exists anywhere in `tools/`:

    $ git grep -nE '/home/|/tmp/claude|\$S/' -- tools/
    (only the ten mutant comments and mutate.sh's header, all of which *describe* the removed
     `$S/mut.sh` rather than depending on it)

**The REUSE step can see the new files — proven, not assumed.** Population derived the way
`tools/gate.sh` derives it (`git ls-files`, minus `slices/*/logs/*` and `LICENSES/*`):

    $ git ls-files | wc -l                                 261
    $ git ls-files | grep -c '^slices/[^/]*/logs/'          188
    $ git ls-files tools/ | wc -l                            20   (11 new this slice)
    all 20 headered by `head -5 … | grep SPDX-License-Identifier`

Then the probe. `tools/mutants/Mr2.py` had its `SPDX-License-Identifier` line removed and the gate
was run whole:

    $ ./tools/gate.sh
      format pass / compile pass / test pass / credo pass / optional deps pass / docs pass
      reuse                      FAIL (261 tracked; 71 in scope, 68 headered + 2 sidecar;
                                       excluded 188 archive + 2 licence text)
          no SPDX-License-Identifier in the file or in a <path>.license sidecar:
            tools/mutants/Mr2.py
      licence files              pass
      GATE FAILED.

The step **names the file** and the headered count drops 69 → 68 against `logs/gate-round1.txt`'s
`69 headered`. This is CONVENTIONS.md's first named instance answered properly: the probe was
planted in a tracked file, so `git ls-files` could see it.

**Restored, and proven restored.**

    $ cp <saved original> tools/mutants/Mr2.py
    $ sha256sum tools/mutants/Mr2.py
      60c3fc1e2e5bfc2b2b4c237ee59a78d525af807d657ce26239bfb11c95e7a52d   (= the pre-probe hash)
    $ git diff --stat HEAD -- tools/          (no output)   EXIT=0
    $ git status --porcelain
      ?? slices/006-harness-honesty/logs/round1.h.md
      ?? slices/006-harness-honesty/logs/round1.h.tree
      ?? slices/006-harness-honesty/logs/round1.m.md
      ?? slices/006-harness-honesty/logs/round1.m.tree

The only paths this lane leaves behind are its own two deliverables. The `lib/` mutant left by the
`SIGKILL` test (h-9) was restored with `git checkout -- lib/beam_mcp/transport/http.ex` and is
absent from the status above.

---

## What I did not check

- **The CI runs themselves.** I did not call `gh`, did not reach the network, and cannot say whether
  runs `34174975336` and `34175931068` exist, failed, or carried those seeds. H-3 is that the record
  contains no archive, not that the numbers are wrong.
- **The 100-run rates were not re-measured.** I verified that each archive's own tally matches what
  FINDINGS says about it, not that a fresh 100 runs would agree.
- **Byte-identity of the scratchpad `fixed_bandit_test.exs`** that `mutation-harness-anchors.txt`
  diffs against, versus the committed file. It is unreachable (h-6), so the anchor diffs cannot be
  confirmed to have been taken against the shipping bytes — and `90e4e99` edited that file after the
  anchor log was written.
- **Whether the archives are byte-for-byte what the commands emitted.** I checked structure —
  headers naming a command, per-run delimiters, terminator lines, internally consistent tallies, no
  seams — which is evidence of wholeness, not proof of it.
- **The mechanism.** Lane `m`'s scope. I read `collect/3`, `settle/2` and the repeat only far enough
  to check that the record describes them accurately, which it does.
- The worktree was not clean while I read it: lane `m`'s uncommitted probe and `mutate.sh` runs were
  live in it throughout. Nothing above depends on the working tree, only on `HEAD` and the archives.
