#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Probe: does tools/archive_sweep.sh's closing tally compare NAMES, or only COUNTS?
#
# The tally exists because round 5 enumerated a file and classified it nowhere. It closes that
# hole for one shape only -- a file that raises the enumerated count -- and leaves open the
# shape where one file leaves the population and another takes its classification slot. The
# counts then balance and the sweep reports a complete pass over a population it did not finish.
#
# The plant is a `git mv` and not a `cp`, because the tally derives its population from
#
#     git ls-files -- "slices/001b-ping-guard/logs/*"
#
# and an untracked file is invisible to that command. Planting outside the population is
# CONVENTIONS.md's first recorded derivation failure, reproduced here on purpose in reverse:
# this probe proves it is planting INSIDE the population by printing the population before and
# after the plant, from that same command.
#
# Untracked files elsewhere in the tree are therefore irrelevant to this probe and are not a
# reason to refuse -- `git ls-files` does not see them. Modified or staged TRACKED files are,
# because the plant and its reversal are themselves tracked operations.
#
#     ./tools/probe_archive_tally.sh > slices/004-gate-honesty/logs/probe-archive-tally.txt 2>&1
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

L=slices/001b-ping-guard/logs
SRC="$L/mutation-a.txt"
DST="$L/mutation-c.txt"

dirty=$(git status --porcelain | grep -v '^?? ')
if [ -n "$dirty" ]; then
  echo "REFUSED: tracked files are modified or staged. This probe renames a tracked file and"
  echo "puts it back; it will not do that over changes it did not make."
  printf '%s\n' "$dirty" | sed 's/^/  /'
  exit 2
fi

planted=0
restore() {
  if [ "$planted" -eq 1 ] && [ -e "$DST" ]; then
    git mv "$DST" "$SRC" >/dev/null 2>&1 || mv "$DST" "$SRC"
  fi
  echo
  echo "=== cleanup: the plant is reverted and the tree is asserted clean ==="
  local left
  left=$(git status --porcelain | grep -v '^?? ')
  if [ -z "$left" ]; then
    echo "  git status --porcelain (tracked): empty. The tree is as it was."
  else
    echo "  NOT CLEAN -- revert by hand:"
    printf '%s\n' "$left" | sed 's/^/    /'
  fi
}
trap restore EXIT

echo "=== the population, as the tally derives it, BEFORE the plant ==="
echo "  \$ git ls-files -- \"$L/*\" | wc -l"
printf '  %s\n' "$(git ls-files -- "$L/*" | wc -l)"
echo "  \$ git ls-files -- \"$L/mutation-*\""
git ls-files -- "$L/mutation-*" | sed 's/^/    /'
echo

echo "=== the plant: a tracked rename inside that population ==="
echo "  \$ git mv $SRC $DST"
git mv "$SRC" "$DST" || { echo "  git mv failed"; exit 2; }
planted=1
echo

echo "=== the population AFTER the plant, from the same command ==="
echo "  \$ git ls-files -- \"$L/*\" | wc -l"
printf '  %s\n' "$(git ls-files -- "$L/*" | wc -l)"
echo "  \$ git ls-files -- \"$L/mutation-*\""
git ls-files -- "$L/mutation-*" | sed 's/^/    /'
echo
echo "  The count is unchanged. mutation-c.txt is enumerated and is classified by nothing:"
echo "  the sweep's mutation loop is \`for m in a b\`, so it still calls verdict() for the"
echo "  now-absent mutation-a.txt. One file left the population, another took its slot, and"
echo "  the two counts the tally compares are both unchanged."
echo

echo "=== ./tools/archive_sweep.sh under the plant ==="
W=$(mktemp -d); trap 'rm -rf "$W"; restore' EXIT
./tools/archive_sweep.sh > "$W/sweep.out" 2>&1
rc=$?
echo "  SWEEP_EXIT=$rc"
echo
echo "  -- every verdict line --"
grep -E '^  => ' "$W/sweep.out" | sed 's/^/  /'
echo
echo "  -- the closing tally, verbatim --"
sed -n '/CLOSING TALLY/,$p' "$W/sweep.out" | sed 's/^/  /'
echo
echo "  -- is mutation-c.txt CLASSIFIED anywhere? Count verdict lines, not mentions: the"
echo "     file is named once by the population echo at the top of the sweep, and a mention"
echo "     is not a classification -- which is the distinction this whole probe is about. --"
echo "  \$ grep -c '=> .*mutation-c' <sweep output>"
printf '  %s\n' "$(grep -c '=> .*mutation-c' "$W/sweep.out")"
echo "  -- and is mutation-a.txt still given a verdict, though it does not exist? --"
echo "  \$ grep '=> .*mutation-a' <sweep output>"
grep '=> .*mutation-a' "$W/sweep.out" | sed 's/^/    /'
echo
echo "=== VERDICT OF THIS PROBE ==="
echo "  A tally that compares names must FAIL here and name both directions:"
echo "    mutation-c.txt  enumerated, classified nowhere"
echo "    mutation-a.txt  classified, no longer enumerated"
echo "  A tally that compares counts reports TALLY BALANCES and exits 0."
echo "  Read the two lines above, not this sentence."
