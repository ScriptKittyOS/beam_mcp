<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Slice 004 — gate honesty

**Base:** `origin/main` = `31bcbff` ("Date the 0.3.0 changelog heading for release").
**Branch:** `slice/004-gate-honesty`. **Worktree:** `beam_mcp-wt/004-gate-honesty`.
**Ships no release.** No version bump, no CHANGELOG entry, no tag, no `mix hex.publish`.

**Files this slice may touch:** `tools/`, `.githooks/`, `.github/`, `slices/004-gate-honesty/`,
plus the nine tracked files named in §2 that the REUSE step cannot presently see.
`mix.exs`, `README.md`, `CHANGELOG.md`, `lib/` and `test/` belong to the concurrent "release"
slice and are **not touched**; if this slice concludes it needs one, that is a report.

The subject of the slice is stated once, because every item below is an instance of it:
**a check that reports on a population it did not derive is not a weaker check, it is a false
one** — it prints `pass` over the thing it never looked at.

---

## 0. Baseline, measured before anything was changed

    $ ./tools/gate.sh                                    # slices/004-gate-honesty/logs/gate-baseline.txt
    == beam_mcp gate ==
      format                     pass
      compile                    pass
      test                       pass
      credo                      pass
      optional deps              pass
      docs                       pass
      reuse                      pass (24 commentable files)
      licence files              pass
    Gate OK.
    GATE_EXIT=0

    $ git ls-files | wc -l
    122
    $ git ls-files -- '*.ex' '*.exs' '*.sh' '*.yml' | wc -l
    24

**122 tracked files. The REUSE step looks at 24 of them and says `pass`.** That is the whole of
item 7's first half in two counts.

---

## 1. Item 6 — SCR-263, `tools/archive_sweep.sh`

### What is actually true now, verified rather than taken from the issue

The issue predates the script's closing tally, so both halves were re-measured on `31bcbff`.

**(a) A `DIFFERS` does not affect the exit status — confirmed, and it is not hypothetical:**

    $ ./tools/archive_sweep.sh > slices/004-gate-honesty/logs/sweep-baseline.txt 2>&1
    SWEEP_EXIT=0
      => full-suite.txt           DIFFERS  (the diff above is the difference)
      => gate.txt                 DIFFERS  (the diff above is the difference)
      => probe-after.txt          DIFFERS  (the diff above is the difference)

Three of thirteen verdicts are `DIFFERS` **today, on `main`**, and the script exits `0`. A
caller that reads the exit code — which is what wiring it into `gate.sh` or CI would do — reads
a clean sweep. `verdict()` prints and returns nothing; only the tally can exit non-zero.

This is also why the issue's trigger condition ("fix before wiring into `gate.sh` or CI") is
the right way round: wiring it first would have wired in a green light.

**(b) The tally compares integers where it claims to compare names — confirmed by reading
lines 203–213.** `ENUM` is `git ls-files -- "$L/*" | wc -l`; `CLASSIFIED` is a counter
incremented once per `verdict` call; `AUTH` is a second `wc -l`. Nothing compares the *set* of
classified names against the *set* of enumerated names, so a file can drop out of the
population and a different one can be classified in its place and the tally still balances —
which is precisely the "quiet" failure the tally was added to prevent.

### The fix

1. `verdict()` sets a `SWEEP_FAIL` flag on any non-`RAW` outcome, and `fetch_check`'s
   `UNCHECKED` branch sets it too — a check that could not run is not a pass, which is the
   rule `gate.sh`'s own header states. The script exits non-zero if the flag is set.
2. `verdict()` records the **path** it classified into a list. The closing tally replaces the
   integer comparison with a `comm` over sorted name sets, printed in **both directions**:
   *enumerated but not classified* and *classified but not enumerated*. The second direction
   is the one the counter could never see.
3. The counts stay, beside the names, because a count is easier to read; the names are what
   decides.

### Consequence, declared now rather than discovered at review

With (1) applied, **the sweep exits non-zero on today's `main`**, because the three `DIFFERS`
are real: `full-suite.txt`, `gate.txt` and `probe-after.txt` were captured at slice 001b's tree
and the tree has since moved (the gate gained a `docs` step; the suite gained tests). That is
drift, not fabrication, and the fixed script says so in its own words rather than being
silenced. **The sweep is therefore not wired into `gate.sh` in this slice** — the gate must
have every step reading `pass`, and re-capturing another slice's archives is that slice's
record to change, not mine. Recorded in FINDINGS and reported.

### Probe (population derived the way the tally derives it)

The tally's population is `git ls-files -- "$L/*"`. The probe therefore plants its violation
with `git mv` — a *tracked* rename — so the file is in that population, which is exactly the
lesson of `CONVENTIONS.md`'s first derivation instance:

    git mv slices/001b-ping-guard/logs/mutation-a.txt \
           slices/001b-ping-guard/logs/mutation-c.txt

`ENUM` is unchanged (29). The `for m in a b` loop still calls `verdict` for the now-absent
`mutation-a.txt`, so `CLASSIFIED` is unchanged (13). `mutation-c.txt` is enumerated and
classified nowhere.

- **Before the fix:** expected `=> TALLY BALANCES` and exit 0. A file left the population
  unnoticed and the instrument reported a complete sweep.
- **After the fix:** expected `TALLY FAILS`, naming `mutation-c.txt` as enumerated-not-classified
  **and** `mutation-a.txt` as classified-not-enumerated, exit non-zero.

Both transcripts archived by redirection. The rename is reverted and `git status` asserted
clean in the same recorded run.

---

## 2. Item 7 — SCR-262, two gate honesty defects

### 2a. The REUSE population is a hand list wearing a derivation's comment

`tools/gate.sh:50-51` says *"every tracked file that can carry a comment carries an SPDX
identifier. Derived from the tracked set, never from a hand list"*, and line 52 then writes the
hand list: `git ls-files -- '*.ex' '*.exs' '*.sh' '*.yml'`. Measured: **24 of 122 tracked
files.** A `.md`, a `.yaml`, a `.toml` or an extensionless file is invisible, and invisible
files report `pass`.

**The fix: the population becomes `git ls-files`, with no glob.** One exclusion survives, and
it is structural rather than convenient:

    slices/*/logs/*

Those are the verbatim archives. `CONVENTIONS.md` — *"A verbatim archive is written by a
command that fetches it, or it does not exist"* — makes editing their bytes the thing that
destroys them, so they cannot carry a header, and three of them are upstream specification
pages whose licence is not this project's to declare. The exclusion is therefore **printed with
its count on every run**, so it can never grow quietly, and its limit is stated rather than
hidden: source code placed under `slices/*/logs/` would escape this step.

Measured, so the size of the change is known before it is made:

    $ git ls-files -- 'slices/*/logs/*' | wc -l
    79
    $ comm -23 <(git ls-files|sort) <(git ls-files -- 'slices/*/logs/*'|sort) | wc -l
    43

and of those 43, the nine the current step cannot see:

    FINDINGS.md                              .gitignore
    HANDOFF.md                               mix.lock
    PLAN.md                                  LICENSE
    slices/002-streamable-http/FINDINGS.md   NOTICE
                                             LICENSES/Apache-2.0.txt

**Coverage for the nine, by the mechanism each file admits:**

- The four `.md` files and `.gitignore` get an SPDX header in the comment syntax they already
  support — the same HTML-comment block every other `.md` in this tree carries.
- `LICENSE`, `NOTICE`, `LICENSES/Apache-2.0.txt` and `mix.lock` get a **`.license` sidecar**,
  which is REUSE's own answer for a file whose bytes must not change (`mix.lock` is rewritten
  by `mix`; the other three are licence text). The step reads `<path>.license` as satisfying
  `<path>`. No new hand list: the sidecar rule is one derived rule applied to any path.

None of the nine is in the "release" slice's file set.

### 2b. The `licence files` verdict vanishes when an earlier step fails

`tools/gate.sh:65` — `[ "$fail" -eq 0 ] && note "licence files" "pass"`. `$fail` is the
**shared** accumulator, so a red `format`, `test`, `credo`, `docs` or `reuse` deletes this
step's line entirely. The header two lines from the top of the same file promises *"Every step
reports its own verdict and its own exit code"*. This step is the one that does not, and the
mode it fails in is the worst one available: the line is not wrong, it is **absent**, and a
reader scanning for `FAIL` finds nothing.

**Fix:** a step-local accumulator, so the step's verdict depends only on the step's own
measurement, and the line is printed unconditionally.

### Probes — `tools/probe_gate_honesty.sh`

One committed, re-runnable harness. It refuses to run on a dirty tree, plants each violation,
runs the **real** `./tools/gate.sh`, reads the **step line** rather than the exit code
(`CONVENTIONS.md`: *"read the step's line, not just the exit code"*), then reverts and asserts
`git status --porcelain` empty.

Every planted file is `git add`ed, because the check derives its population from `git ls-files`
and an unadded file is invisible — instance #1 in `CONVENTIONS.md`, reproduced deliberately as
probe P0 so the harness demonstrates on itself that it is planting inside the population.

| probe | plants | before the fix | after the fix |
|---|---|---|---|
| P0 | unheadered `probe.yaml`, **not** `git add`ed | `reuse pass` | `reuse pass` — recorded as the control: the probe, not the check, is at fault |
| P1 | unheadered `probe.yaml`, `git add`ed | `reuse pass` | `reuse FAIL`, naming the file |
| P2 | unheadered `PROBE` (no extension), `git add`ed | `reuse pass` | `reuse FAIL`, naming the file |
| P3 | unheadered `probe.md`, `git add`ed | `reuse pass` | `reuse FAIL`, naming the file |
| P4 | headered `probe.yaml` + delete its content's header only | `reuse pass` | `reuse FAIL` |
| P5 | unheadered `.yaml` **and** `git mv NOTICE NOTICE.x` | `licence files` line **absent** | both lines `FAIL`, both present |
| P6 | `git mv LICENSE LICENSE.x` alone | `licence files FAIL` | `licence files FAIL` (unchanged; the guard is only visible behind an earlier failure) |

P5 is the one that matters for 2b and it is the pair, not the single: a missing licence file
**with an earlier step already red** is the only input that distinguishes the two versions.
P6 exists so the table shows the case that already worked and is not claimed as new coverage.

Additionally, a **mutation** on the fixed script: revert the population to the four-extension
glob and re-run P1–P3; all three must return to `pass`. A probe that cannot go green under the
old code is not testing the change.

---

## 3. Item 8 — SCR-249, `mix docs` as a gate step

**The coordinator has confirmed this shipped and it is not this slice's work.** Verified
independently: `tools/gate.sh:41-48` reads `mix docs`'s *output* because the command exits 0 on
a warning, and the baseline above shows the step present and `pass`. Nothing to build.

What remains is the *honesty* question, and it is **time-boxed and optional**. Four routes will
be checked and each answered yes or no with a measurement; **if none is real, that is the
report and no change is made.**

1. Can `warning:` reach the count from **dependency compilation** rather than from docs?
2. Can a **tracked file's own content** put the literal `warning:` into `mix docs` output?
3. Does the step **leave `doc/` behind**, and does that change any later step's result?
4. Can the step **fail for a reason unrelated to docs** and report it as a docs failure?

Investigated in a throwaway `git clone` under the scratchpad, never in the shared worktree,
because probing (2) means editing `lib/` and `lib/` belongs to the "release" slice.

---

## 4. Item 9 — SCR-265, `tools/signoff.sh`

`tools/` contains `archive_sweep.sh`, `gate.sh`, `measure_body.exs`, `probe_optional_deps.sh`,
`probe_ping.exs`. Verified: **no signoff script.** No reference implementation is available to
this slice, so the design is derived from the requirement.

**The requirement, from the failure it comes from.** Slice 001b ran an extra review round
because a version bump moved the tree after both lanes had approved it. The two facts a
signoff must carry are therefore *what was read* and *whether it is still what is there* — and
the second must **refuse**, not assume. Slice 002 already reached for this by hand: its logs
carry `round3.r1.tree`, `round4.s1.tree` and four more, bare 40-hex files with nothing that
reads them. Mechanising an existing manual practice, not inventing one.

### Design

    tools/signoff.sh record <slice-dir> <round> <lane> <approve|changes-required> [note]
    tools/signoff.sh verify <slice-dir>

**The hash a signoff binds is the tree with the signoff records removed.** Without that the
mechanism eats itself: recording lane r1's verdict changes the tree and so invalidates it
before lane r2 records. Computed with git's own plumbing, in a scratch index, so the value is
reproducible by anyone from the same commit:

    GIT_INDEX_FILE=$tmp git read-tree HEAD
    GIT_INDEX_FILE=$tmp git rm -r --cached -q slices/*/signoff
    GIT_INDEX_FILE=$tmp git write-tree

`slices/<slice>/signoff/` is the one directory the tool owns and the one it excludes. `verify`
enforces that nothing else hides there: every file under it must be a `*.signoff` record or the
tool's own `verify.txt`, or `verify` refuses. Otherwise "excluded from the reviewed tree"
would be a place to put code.

**Both commands refuse rather than assume, and each refusal is a named exit:**

| condition | result |
|---|---|
| working tree has modified/deleted tracked files, or untracked files outside `slices/*/signoff/` | refuse — the hash would not describe what the reviewer read |
| `verify` over a slice with **zero** records | **refuse** — no signoff must never read as signed off. This is the whole class of defect this slice is about, so the tool must not contain it |
| a record's tree hash ≠ the current review tree | `STALE`, refuse — this is 001b's failure, mechanised |
| any record's verdict is `changes-required` | refuse |
| a record is unparseable or missing a field | refuse — not skipped |

### Probe — `tools/probe_signoff.sh`

Runs entirely inside a `mktemp -d` git repository it builds itself, so it touches nothing.
Its population is derived the way `verify` derives it: records are created **by calling
`signoff.sh record`**, and the tree is moved **by a real commit**, not by editing a hash.

| probe | plants | expected |
|---|---|---|
| S1 | two `approve` records at tree T, nothing else | `verify` exits 0 |
| S2 | S1, then a commit changing a tracked file | `verify` exits non-zero, both records `STALE` |
| S3 | S1, then a commit that changes **only** `slices/*/signoff/` | `verify` exits 0 — the exclusion is load-bearing and this proves it, rather than asserting it |
| S4 | no records at all | `verify` exits non-zero. If this passes, the tool is the defect it was written against |
| S5 | one `approve`, one `changes-required` | `verify` exits non-zero |
| S6 | a stray `notes.txt` under `slices/*/signoff/` | `verify` refuses |
| S7 | a record with its `tree:` line deleted | `verify` refuses, does not skip |

**Mutation on the fixed tool** — remove the `git rm -r --cached slices/*/signoff` line and
re-run: S1 and S3 must break. An exclusion whose removal changes nothing was never load-bearing.

### Not wired into `gate.sh` or CI, and the reason is stated

Wiring `verify` into the gate would demand signoff records on every push, including the push
that introduces the tool and including the concurrent "release" slice's branch. That is a
policy decision for the owner, not a side effect of adding a script. **Reported, not taken.**

Instead this slice **uses** it: each review lane records its verdict with
`tools/signoff.sh record`, and `verify` is run and quoted before the PR is opened. A tool whose
first use is its own slice is the cheapest available demonstration that it works on a real tree.

---

## 5. Commits

Each is one thing, each carries its own evidence, each is `git commit -s`, and none carries a
tool-attribution trailer.

1. **cover the nine tracked files the REUSE glob cannot see** — five headers, four `.license`
   sidecars. Message quotes the derivation command and its nine-line output.
2. **derive the REUSE population from the tracked set** — `gate.sh` + `tools/probe_gate_honesty.sh`.
   Message carries the red: the new step run against the pre-commit-1 tree, naming nine files.
3. **the `licence files` verdict does not depend on earlier steps** — `gate.sh` + P5 in the
   probe harness. Message carries the red: the P5 transcript in which the line is absent.
4. **`archive_sweep.sh`: a `DIFFERS` fails the run and the tally compares names** — message
   carries `SWEEP_EXIT=0` beside three `DIFFERS`, and the `TALLY BALANCES` under the planted
   rename.
5. **`tools/signoff.sh` + `tools/probe_signoff.sh`** — message carries S2 and S4.
6. **slice record** — this PLAN, `FINDINGS.md`, and the logs.

Order matters: 1 before 2 so no commit leaves the gate red, and the red for 2 is captured by
applying 2's `gate.sh` alone against the tree before 1.

## 6. Acceptance

- `./tools/gate.sh` exits 0 with **every step line reading `pass`** — no ratchet, no baseline.
  Archived verbatim by redirection at the final tree.
- Every probe table above has both a before and an after transcript, each written by the
  command that produced it.
- Every fix has at least one planted violation the fixed check catches and the unfixed check
  does not, with the plant made through the same command the check derives its population from.
- Up to three review rounds, lanes spawned by this slice, each recording the tree hash it read
  via `tools/signoff.sh`. No commit on a changes-required verdict.
- A PR against `main`, not merged, with every check's conclusion read from the **jobs** API.
  A check reporting `steps=0` did not run and is not a verdict.

## 7. Known limits, written before the work rather than after

- `slices/*/logs/` is outside the REUSE step. Source placed there escapes it.
- The fixed `archive_sweep.sh` exits non-zero on `main` because three archives have drifted
  from a moved tree. Naming the drift is the fix; re-capturing those archives is slice 001b's
  record, not this slice's.
- `tools/signoff.sh` binds a *tree*, which is what the reviewer read. It cannot know whether
  the reviewer read it.
- Nothing here reduces the honesty of a check that is already honest, and no step is added to
  `gate.sh` that could pass without measuring something.
