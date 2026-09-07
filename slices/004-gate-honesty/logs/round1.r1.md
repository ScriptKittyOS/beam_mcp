<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Round 1, lane r1 — mechanism

**Tree read:** `9a7998d1ae1f2d8ca8b4a422b0c579c24f4aae1b` (commit `6a30cb2`), pinned in
`round1.r1.tree`.
**Remit:** does each script do what its own comments claim, on the machines it will run on.
**Verdict: CHANGES-REQUIRED.** Two blocking findings.

## Lane independence — stated first, because it is the weakest part of this record

Both lanes of every round in this slice were run by the same agent. Subagent spawning was
withheld for this run, so "two independent lanes" here means two separate passes with different
remits and different evidence, not two parties. That is weaker than what `PLAN.md` §6 asks for
and it is recorded rather than papered over: a lane cannot be independent of itself, and the
findings below should be read as the product of one reviewer working twice.

## R1-A (blocking) — `tools/gate.sh` reports `pass` over 10 of 145 files on bash 3.2

`gate.sh` used `declare -A tracked` and `tracked["$f"]=1`. Bash 3.2 — the bash every stock macOS
ships — has no `-A`, so that becomes an **indexed** array whose subscript is evaluated as
**arithmetic**. Simulated by substituting `declare -a` for `declare -A`, which is what bash 3.2
effectively leaves you with, changing nothing else:

    $ diff tools/gate.sh $S/gate.bash3.sh
    90c90
    < declare -A tracked=()
    ---
    > declare -a tracked=()   # SIMULATES bash 3.2, which has no -A

    $ bash $S/gate.bash3.sh
    == beam_mcp gate ==
      ...
      reuse                      pass (10 tracked; 10 in scope, 9 headered + 0 sidecar; excluded 0 archive + 0 licence text)
      licence files              pass
    Gate OK.
    EXIT=0

    stderr, in its entirety, 2 lines:
      line  91: .formatter.exs: syntax error: operand expected (error token is ".formatter.exs")
      line 103: LICENSE.license: syntax error: invalid arithmetic operator (error token is ".license")

The arithmetic error is fatal to its enclosing command, so each loop **aborts at its first
offending path** — the first at once, the second after ten files. The step then prints `pass`
over ten files out of 145 and the gate exits 0.

This is the exact defect the slice exists to remove — a check reporting `pass` over a population
it never looked at — **reintroduced by the fix for it**, with two lines on stderr as the only
sign. It is the more serious of the two findings by some distance, because the old glob at least
looked at the files it claimed.

**Required:** remove the dependency rather than document it.

## R1-B (blocking) — a symlink walks through `signoff/`'s whitelist

`tools/signoff.sh verify` enumerated the excluded directory with `find -mindepth 1 -type f`,
which does not match a symlink. A link was therefore seen by neither the file loop nor the
subdirectory check. Demonstrated with the link pointing at an **already tracked** file, so the
reviewed tree does not move and `STALE` cannot be what refuses:

    === HEAD now carries, under the excluded directory: ===
      120000 blob 5f9d404e...	slices/test/signoff/anything.sh
      100644 blob 1575c0ea...	slices/test/signoff/round1.r1.signoff
      100644 blob 0ae24ecc...	slices/test/signoff/round1.r2.signoff
      100644 blob a1b4159e...	slices/test/signoff/verify.txt
    === verify ===
       2 record(s), all approve, all on the tree in front of you.
    VERIFY_EXIT=0

    === and a plain file with the same name is refused, for contrast ===
    SIGNOFF REFUSED -- slices/test/signoff/anything.sh is not a *.signoff record.
    VERIFY_EXIT=1

The script's own comment says the exclusion "must not become a place to put code". A link is
how you put code there. **Required:** check the entry type before the name, and test `-L`
before `-f`, because `-f` follows the link.

## Not blocking, recorded

- `head -5 "$f.license"` reads the sidecar from the **worktree** while its membership is
  tested in the **index**. Consistent with every other read in `gate.sh`, which runs against
  the worktree throughout, so it is a limit rather than a defect.
- Paths containing newlines would break both the `while read` loops and the `missing` list.
  `git ls-files` quotes such paths, and both the population and the lookup come from the same
  invocation, so they cannot disagree. Recorded, not fixed.
