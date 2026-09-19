#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# The two hand edits to docs/public-api.txt the census cannot see, because it reads the tree
# alone (G-076, measured by a review lane: the whole gate green on each):
#
#   1. a baseline line deleted outright -- the writer never deletes a line, so a non-comment
#      line present at the base and absent at the head, whose entry (the text before its
#      markers) does not reappear, is a hand deletion of a public entry;
#   2. a marker back-dated -- a `since=`, `deprecated_since=` or `removed_in=` value ARRIVING
#      in this change as a release number that is not above the base CHANGELOG's highest
#      `## [N]` heading: one it already lists, or a phantom between two releases (a lane
#      measured `removed_in=0.6.5` passing the first draft) -- a change dressed as one that
#      already shipped. The release commit writes its own, higher number, and passes.
#
# Pure: three files in, a verdict out, so a probe can plant on copies. The gate feeds it the
# base from `git show origin/main:...` and the head from the tree.
#
#     tools/baseline_diff.sh <base public-api.txt> <head public-api.txt> <base CHANGELOG.md>
# exit 0: neither edit; 1: one or both (each named); 2: usage.
set -uo pipefail
[ $# -eq 3 ] || { echo "usage: tools/baseline_diff.sh <base-baseline> <head-baseline> <base-changelog>" >&2; exit 2; }
base=$1 head=$2 changelog=$3
for f in "$base" "$head" "$changelog"; do [ -r "$f" ] || { echo "unreadable: $f" >&2; exit 2; }; done

entries() { grep -v '^#' "$1" | grep -v '^[[:space:]]*$' | sed -E 's/( (since|deprecated_since|removed_in)=[^ ]+)+$//' | sort -u; }
# Per entry, so a NEW line arriving with a number an old line already carries is still an arrival.
markers() { grep -v '^#' "$1" | awk '{for (i=2;i<=NF;i++) if ($i ~ /^(since|deprecated_since|removed_in)=/) print $1" "$2" "$3" "$i}' | sort -u; }

fail=0
# 1. Deleted entries.
deleted=$(comm -23 <(entries "$base") <(entries "$head"))
if [ -n "$deleted" ]; then
  echo "FAIL: public entries deleted from the baseline by hand (the writer never deletes a line; a removal is marked removed_in= and stays):"
  printf '%s\n' "$deleted" | sed 's/^/  /'
  fail=1
fi
# 2. Markers arriving with an already-released number.
highest=$(grep -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' "$changelog" | tr -d '#[] ' | sort -V | tail -1)
arriving=$(comm -13 <(markers "$base") <(markers "$head"))
backdated=""
while IFS= read -r m; do
  [ -n "$m" ] || continue
  v=${m##*=}
  [ "$v" = "Unreleased" ] && continue
  # Not above the highest released heading: equal to it, below it, or between two releases.
  if [ -z "$highest" ] || [ "$v" = "$highest" ] || [ "$(printf '%s\n%s\n' "$highest" "$v" | sort -V | tail -1)" != "$v" ]; then
    backdated="${backdated}${m}"$'\n'
  fi
done <<< "$arriving"
if [ -n "$backdated" ]; then
  echo "FAIL: markers arriving with a release number not above the base CHANGELOG's highest heading ($highest) -- a change dressed as one that shipped:"
  printf '%s' "$backdated" | sort -u | sed 's/^/  /'
  fail=1
fi
if [ "$fail" -eq 0 ]; then
  echo "pass ($(entries "$head" | wc -l | tr -d ' ') entries at the head, none deleted; $(printf '%s\n' "$arriving" | grep -c . || true) marker(s) arriving, none back-dated)"
fi
exit "$fail"
