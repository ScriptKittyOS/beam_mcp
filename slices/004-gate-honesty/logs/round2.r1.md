<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Round 2, lane r1 — mechanism

**Tree read:** `7ae4f8330a27316e1fa7d4927d728800575ce438` (commit `08ecf7d`), pinned in
`round2.r1.tree` and in `signoff/round2.r1.signoff`.
**Remit:** what is each mechanism actually resting on.
**Verdict: CHANGES-REQUIRED.** One blocking finding.

Round 1's fixes were re-checked first and hold: `tools/gate.sh` carries no bash-4-only
construct on a live line (P9 `pass`), and a symlink under `signoff/` is refused by name in S8.
Probes P0–P9 all read as expected at this tree (`logs/probe-gate-honesty-round2.txt`).

## R2-A (blocking) — the signoff exclusion depended on which `grep` is first on `PATH`

`review_tree()` excluded the signoff paths with

    git ls-tree -r -z --name-only HEAD | grep -z -E '^slices/[^/]+/signoff/' > "$list"

`-z` does not mean one thing. Measured on the machine this was written on, where **both** greps
are installed:

    $ grep --help | grep -E '^\s+-z'
        -z, --decompress                                                <- ugrep 7.8.4, first on PATH
    $ /usr/bin/grep --help | grep -- --null-data
      -z, --null-data           a data line ends in 0 byte, not newline  <- GNU grep 3.11

It produced the right answer here. That is the problem: it produced the right answer for a
reason nobody had checked, and the failure mode is quiet in the expensive direction. A filter
that silently matches nothing removes the exclusion; every record then reads `STALE`; and a tool
that always refuses is a tool that gets switched off — which is R1-C's failure arriving by
another route, three commits after R1-C was fixed.

**Required:** remove the pattern language. A shell glob does not cross `/`, so
`for d in slices/*/signoff` means exactly what it looks like, and `git rm -r --cached -- "$d"`
needs no pattern at all.

Two alternatives were tried and rejected with a measurement rather than an opinion:

    $ git ls-tree -r -z --name-only HEAD -- ':(glob)slices/*/signoff/**'
    fatal: pathspec magic not supported by this command: 'glob'
    $ git ls-tree -r --name-only HEAD -- 'slices/*/signoff/*'
    (no output at all)

A git pathspec `*` matches `/`, so the plain form also reaches `slices/a/b/signoff` — wider than
the sentence describing it — and the one form that would mean what the sentence says is rejected
by the command.

## Not blocking, recorded

- `gate.sh` reads a sidecar's bytes from the worktree while testing membership in the index.
  Unchanged from round 1 and still a limit rather than a defect: the gate runs against the
  worktree throughout.
- `signoff.sh`'s `field()` takes the first match for a key. A hand-edited record with two
  `tree:` lines would be read by the first. It cannot be used to make `verify` pass, because
  the value read is still compared against the computed tree.
