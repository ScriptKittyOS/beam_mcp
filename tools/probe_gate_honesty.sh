#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Probes for the two gate steps that used to report on things they had not looked at:
# the REUSE population, and the `licence files` verdict.
#
# THE RULE THIS SCRIPT EXISTS TO OBEY. CONVENTIONS.md, "A probe's population must be derived
# the way the checked mechanism derives it": the REUSE step derives its population from
# `git ls-files`, so a planted file that is not `git add`ed is INVISIBLE to it and the step
# prints `pass` -- which is a fact about the probe, not about the check. That exact failure is
# instance #1 in that section, and it happened to this check. So every plant here is `git add`ed,
# and P0 exists to demonstrate the failure deliberately rather than to be trusted not to make it.
#
# AND: read the STEP LINE, not the exit code. A gate that exits 1 tells you nothing about which
# step objected -- that is the same convention's second sentence. Every probe below reports the
# `reuse` line, the `licence files` line, and whether every OTHER step still read `pass`, so a
# probe cannot be scored on a failure it did not cause.
#
#     ./tools/probe_gate_honesty.sh > slices/004-gate-honesty/logs/probe-gate-honesty.txt 2>&1
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

# Untracked files elsewhere are irrelevant: the REUSE population is `git ls-files`, which does
# not see them. Modified or staged TRACKED files are not, because the plants and their reversal
# are tracked operations and this script will not run them over changes it did not make.
dirty=$(git status --porcelain | grep -v '^?? ')
if [ -n "$dirty" ]; then
  echo "REFUSED: tracked files are modified or staged."
  printf '%s\n' "$dirty" | sed 's/^/  /'
  exit 2
fi

W=$(mktemp -d)
PLANTED=""     # paths created by this script
MOVED=""       # "from>to" tracked renames made by this script

cleanup() {
  local p pair from to
  for pair in $MOVED; do
    from="${pair%%>*}"; to="${pair##*>}"
    [ -e "$to" ] && { git mv "$to" "$from" >/dev/null 2>&1 || mv "$to" "$from"; }
  done
  for p in $PLANTED; do
    git rm -q --cached "$p" >/dev/null 2>&1
    rm -f "$p"
  done
  rm -rf "$W"
  echo
  echo "=== cleanup ==="
  local left
  left=$(git status --porcelain | grep -v '^?? ')
  if [ -z "$left" ]; then
    echo "  git status --porcelain (tracked): empty. Every plant is reverted."
  else
    echo "  NOT CLEAN -- revert by hand:"; printf '%s\n' "$left" | sed 's/^/    /'
  fi
}
trap cleanup EXIT

plant() { # plant <path> <content...>   -- creates the file and git adds it
  local p="$1"; shift
  printf '%s\n' "$*" > "$p"
  git add -f "$p" || return 1
  PLANTED="$PLANTED $p"
}
plant_untracked() { # plant_untracked <path> <content...>  -- creates it and does NOT git add
  local p="$1"; shift
  printf '%s\n' "$*" > "$p"
  PLANTED="$PLANTED $p"
}
rename_tracked() { # rename_tracked <from> <to>
  git mv "$1" "$2" && MOVED="$MOVED $1>$2"
}
unplant_all() {
  local p pair from to
  for pair in $MOVED; do
    from="${pair%%>*}"; to="${pair##*>}"
    [ -e "$to" ] && { git mv "$to" "$from" >/dev/null 2>&1 || mv "$to" "$from"; }
  done
  MOVED=""
  for p in $PLANTED; do git rm -q --cached "$p" >/dev/null 2>&1; rm -f "$p"; done
  PLANTED=""
}

# Run the REAL gate and report the two step lines plus the state of every other step.
run_gate() { # run_gate <probe-id> <what was planted>
  local id="$1" what="$2" rc other
  ./tools/gate.sh > "$W/gate.out" 2>&1; rc=$?
  echo "  -- $id: $what"
  echo "     in the population?  \$ git ls-files | grep -c '^probe\\|^PROBE'  ->  $(git ls-files | grep -c '^probe\|^PROBE')"
  printf '     reuse line        :  %s\n' "$(grep -E '^  reuse ' "$W/gate.out" | sed 's/^  *//' || true)"
  printf '     licence files line:  %s\n' "$(grep -E '^  licence files ' "$W/gate.out" | sed 's/^  *//' || true)"
  printf '     licence files line count: %s   (0 means the step printed NOTHING)\n' \
         "$(grep -c '^  licence files ' "$W/gate.out")"
  other=$(grep -E '^  (format|compile|test|credo|optional deps|docs) ' "$W/gate.out" | grep -cv ' pass$')
  printf '     other steps not pass: %s   (so the objection above is this step, not a side effect)\n' "$other"
  printf '     GATE_EXIT=%s\n' "$rc"
  grep -E '^ +(probe|PROBE)[^ ]*$' "$W/gate.out" | sed 's/^ */     named by the step: /'
  echo
}

echo "=== the population, as the REUSE step derives it ==="
echo "  \$ git ls-files | wc -l"
printf '  %s\n' "$(git ls-files | wc -l)"
echo "  This is the whole of the derivation. Everything below is planted into THIS set or"
echo "  deliberately outside it."
echo

echo "=== P0 -- the control, and it is the probe failing rather than the check ==="
echo "  An unheadered probe.yaml that is NOT git added. The step derives its population from"
echo "  git ls-files, so the file does not exist as far as the check is concerned and the step"
echo "  is RIGHT to say pass. Recorded so no later probe here can be read as proof by accident."
plant_untracked probe-gate-honesty.yaml "key: value"
run_gate P0 "unheadered probe-gate-honesty.yaml, NOT git added"
unplant_all

echo "=== P1 -- .yaml, git added. The extension the old glob ('*.yml') was one letter from ==="
plant probe-gate-honesty.yaml "key: value"
run_gate P1 "unheadered probe-gate-honesty.yaml, git added"
unplant_all

echo "=== P2 -- no extension at all. Nothing a glob on extensions can ever reach ==="
plant PROBEGATEHONESTY "some text"
run_gate P2 "unheadered extensionless PROBEGATEHONESTY, git added"
unplant_all

echo "=== P3 -- .md. Every other .md in this tree carries a header; this step never read one ==="
plant probe-gate-honesty.md "# probe"
run_gate P3 "unheadered probe-gate-honesty.md, git added"
unplant_all

echo "=== P4 -- the same .yaml with a .license sidecar. Proves P1's FAIL is about the missing"
echo "    identifier and not about the extension, and that the sidecar route actually works ==="
plant probe-gate-honesty.yaml "key: value"
plant probe-gate-honesty.yaml.license "SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0"
run_gate P4 "unheadered probe-gate-honesty.yaml + a sidecar carrying the identifier"
unplant_all

echo "=== P5 -- THE ONE THAT MATTERS FOR THE SECOND DEFECT ==="
echo "  A missing licence file AND an earlier step already red. That pair is the only input"
echo "  that distinguishes a step-local verdict from one guarded by the shared accumulator:"
echo "  with \`[ \"\$fail\" -eq 0 ] && note \"licence files\" \"pass\"\`, the line VANISHES. Not a"
echo "  wrong verdict -- no verdict, in a script whose header promises every step reports one."
echo "  Watch 'licence files line count'. Zero is the defect."
echo
echo "  The plant here is an unheadered .sh and NOT the .yaml used above, deliberately: .sh is"
echo "  in the OLD four-extension population as well as the new one, so this probe turns the"
echo "  reuse step red under both versions of the script and the only thing that changes"
echo "  between the before and after runs is the licence-files guard. A probe whose plant is"
echo "  invisible to the version it is comparing against measures two changes at once."
plant probe-gate-honesty.sh "echo probe"
rename_tracked NOTICE NOTICE.probe-moved
run_gate P5 "unheadered probe-gate-honesty.sh (reuse red under BOTH populations) + NOTICE renamed away"
unplant_all

echo "=== P6 -- the control for P5: a missing licence file with NOTHING else red ==="
echo "  This case worked before the fix and works after it. It is here so the table shows what"
echo "  is not new coverage, rather than letting P5's result stand for both."
rename_tracked LICENSE LICENSE.probe-moved
run_gate P6 "LICENSE renamed away, nothing else planted"
unplant_all

echo "=== P7 -- the probe P5 was SUPPOSED to be, added because P5 measured identical before"
echo "    and after and therefore tested nothing ==="
echo "  CORRECTION, APPENDED RATHER THAN SUBSTITUTED. PLAN.md 2a's table predicts that under"
echo "  the shared accumulator P5 shows the 'licence files' line ABSENT. It does not, and the"
echo "  before-transcript says so: 'licence files line count: 1', reading 'FAIL -- NOTICE"
echo "  missing'. Reading the old code explains why -- only the PASS branch was guarded:"
echo
echo "      for f in LICENSE NOTICE LICENSES/Apache-2.0.txt; do"
echo "        [ -f \"\$f\" ] || { note \"licence files\" \"FAIL -- \$f missing\"; fail=1; }   <- unguarded"
echo "      done"
echo "      [ \"\$fail\" -eq 0 ] && note \"licence files\" \"pass\"                          <- guarded"
echo
echo "  So the input that vanishes the line is the OPPOSITE of P5's: an earlier step red while"
echo "  every licence file is PRESENT. P5 renames NOTICE away and thereby forces the one branch"
echo "  that always printed. P7 plants the earlier red and leaves the licence files alone."
echo "  Before the fix the line count is 0; after it, 1 reading pass. That is the anchor 2b had"
echo "  none of, and it is the shape this whole slice is about: not a wrong verdict, no verdict."
plant probe-gate-honesty.sh "echo probe"
run_gate P7 "unheadered probe-gate-honesty.sh, ALL licence files present"
unplant_all

echo "=== P8 -- the sidecar looked up on disk instead of in the tracked set ==="
echo "  P4 proves a sidecar covers its file. It does not ask WHERE the step looked for the"
echo "  sidecar. The step's population is git ls-files; its sidecar test was \`[ -f ]\`, a"
echo "  filesystem test -- so an UNTRACKED sidecar covered a TRACKED file on the author's disk"
echo "  and did not exist in a fresh clone or in CI. CONVENTIONS.md instance #1, on the"
echo "  coverage side of the same check. Measured red: logs/red-sidecar-untracked.txt."
plant probe-gate-honesty.yaml "key: value"
plant_untracked probe-gate-honesty.yaml.license "SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0"
run_gate P8 "unheadered probe-gate-honesty.yaml + a sidecar that is NOT git added"
unplant_all

echo "=== what to read ==="
echo "  P1, P2, P3      reuse must FAIL and NAME the file. Under the four-extension glob all"
echo "                  three read pass, because the file was never in the population."
echo "  P4              reuse must pass -- the sidecar is the covering mechanism, not an"
echo "                  exception to the population."
echo "  P5              'licence files line count' must be 1 and the line must read FAIL."
echo "                  Under the shared accumulator it is 0."
echo "                  MEASURED FALSE -- it is 1 under both, see P7. P5 is retained as the"
echo "                  record of a prediction the run refuted, not as coverage."
echo "  P7              'licence files line count' must be 1 and the line must read PASS."
echo "                  Under the shared accumulator it is 0. This is 2b's only real anchor."
echo "  P8              reuse must FAIL and name probe-gate-honesty.yaml. With the sidecar"
echo "                  tested by [ -f ] it reads pass and counts the sidecar."
echo "  P0, P6          unchanged by either fix, and recorded as such."
