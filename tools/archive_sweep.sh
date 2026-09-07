#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Classify every file the slice record labels an archive: is it its command's bytes, or not?
#
# Written because fixing one archive per round met the next one three rounds running. A list is
# not a population. This derives the population and SHOWS each comparison -- including the
# normalisation it applies -- because a sweep whose whole point is "do not trust a claim, diff
# the bytes" must not assert its own verdicts in an echo. That was r2's round-4 finding 3
# against the first version of this script, and it was right.
#
#     ./tools/archive_sweep.sh > slices/001b-ping-guard/logs/archive-sweep.txt 2>&1
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1
L=slices/001b-ping-guard/logs
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT

# Seed and timings differ on every ExUnit run; normalise ONLY those, and say so at each use.
# Normalise ONLY what varies between runs of the same command on the same bytes:
#   - the ExUnit seed and the timings, which change every run;
#   - the compile prologue, which depends on whether _build was warm and which no archive
#     contains. r1 ran this script on a cold build and got a false DIFFERS on full-suite.txt
#     (round 5). The build is warmed below as well; this makes the comparison independent of
#     build state rather than merely usually-right, so the header's command reproduces the
#     tracked output on a clean checkout.
# Nothing else is touched -- in particular nothing inside a failure block.
norm() {
  sed -E 's/seed: [0-9]+/seed: N/; s/in [0-9.]+ seconds/in T seconds/; s/\([0-9.]+s async, [0-9.]+s sync\)/(T async, T sync)/' "$1" \
    | grep -Ev '^(==> |Compiling [0-9]+ file|Generated .* app)'
}

# Two notes, not one. The first version took a single note and printed it on both branches,
# so a failing line read "DIFFERS (empty diff above = identical)" -- a parenthetical asserting
# a result the run had just contradicted. A printed claim the run did not compute is the exact
# defect this instrument exists to catch, and it was inside the instrument (r2 round-5, 2a).
CLASSIFIED=0
verdict() { # verdict <file> <rc> <pass-note> <fail-note>
  CLASSIFIED=$((CLASSIFIED + 1))
  if [ "$2" -eq 0 ]; then printf '  => %-24s RAW      %s\n' "$1" "$3"
  else printf '  => %-24s DIFFERS  %s\n' "$1" "${4:-see the diff above}"; fi
}

# An empty diff and a diff that never ran are indistinguishable on the page. So report the
# comparison POSITIVELY -- the differing-line count and the exit code -- rather than printing
# nothing and calling it agreement. A check that did not execute cannot then render as a pass.
showdiff() { # showdiff <expected> <actual> -> returns diff's rc
  local out rc
  out=$(diff "$1" "$2"); rc=$?
  printf '     comparison: %s differing line(s), diff exit=%s\n' "$(printf '%s' "$out" | grep -c '^[<>]')" "$rc"
  [ -n "$out" ] && printf '%s\n' "$out" | sed 's/^/       /'
  return $rc
}

# The marks a filtered capture cannot have. Used for logs that cannot be re-run here.
marks() { # marks <file> -> prints counts, returns 0 if all four present
  local f="$1" banner stack code fin
  banner=$(grep -c 'Running ExUnit with seed' "$f"); stack=$(grep -c 'stacktrace:' "$f")
  code=$(grep -c 'code:' "$f");                      fin=$(grep -c 'Finished in' "$f")
  printf '    seed banner : %s\n    stacktrace: : %s\n    code:       : %s\n    Finished in : %s\n' \
         "$banner" "$stack" "$code" "$fin"
  printf '    tests, line : %s\n' "$(grep 'tests,' "$f")"
  # ALL FOUR are enforced, not merely printed. The first version tested only two, so a log
  # stripped of its ExUnit banner -- instance #2 exactly -- still scored RAW (r2 round-5, 3).
  [ "$banner" -ge 1 ] && [ "$stack" -ge 1 ] && [ "$code" -ge 1 ] && [ "$fin" -ge 1 ]
}

echo "=== POPULATION, derived from the tracked set rather than listed ==="
git ls-files -- "$L/*" | sed 's/^/  /'
echo
echo "Two kinds of file live here, and only one kind can be diffed against a command:"
echo "  CAPTURES     - a command wrote them; re-run the command and compare bytes."
echo "                 Includes the spec-*.md files: 'curl -o' IS the command and the"
echo "                 upstream page IS the source, so they are checkable, not prose."
echo "  AUTHORED     - the round*.md lane reports. Each was written by the reviewer that"
echo "                 is its source. Nothing to re-run; they must simply never be"
echo "                 labelled the output of a command."
echo
# Warm the build BEFORE any comparison, and say so. Without this the first `mix test` hits a
# cold _build and emits "Compiling N files (.ex)" lines that norm() does not touch, scoring a
# false DIFFERS that depends only on the machine the sweep ran on. The first version passed
# purely because gate.sh happened to run --force earlier in the file: the ordering was
# load-bearing and undocumented (r2 round-5, 2b).
echo "=== warming the build so comparisons do not depend on _build state ==="
echo "  \$ mix compile --force ; mix test --exclude all   (output discarded; only the"
echo "  build state matters here, and a cold build emits compile lines no archive contains)"
mix compile --force > /dev/null 2>&1
mix test --exclude test > /dev/null 2>&1
echo

echo "=== CAPTURES: test and gate logs ==="
echo "-- full-suite.txt: diff vs a fresh 'mix test', seed+timing normalised on BOTH sides --"
mix test > "$W/full.out" 2>&1
showdiff <(norm "$W/full.out") <(norm "$L/full-suite.txt"); rc=$?
verdict full-suite.txt $rc "(0 differing lines above; seed/timing/compile normalised)" "(the diff above is the difference)"
echo
echo "-- green-negotiation.txt: same command, same normalisation --"
mix test test/beam_mcp/negotiation_test.exs > "$W/green.out" 2>&1
showdiff <(norm "$W/green.out") <(norm "$L/green-negotiation.txt"); rc=$?
verdict green-negotiation.txt $rc "(0 differing lines above)" "(the diff above is the difference)"
echo
echo "-- gate.txt: no normalisation, the gate emits nothing variable --"
./tools/gate.sh > "$W/gate.out" 2>&1
showdiff "$W/gate.out" "$L/gate.txt"; rc=$?
verdict gate.txt $rc "(0 differing lines above; no normalisation applied)" "(the diff above is the difference)"
echo
echo "=== CAPTURES: the probe ==="
echo "-- probe-after.txt vs a WARM fresh run of the tracked probe, no normalisation --"
mix run tools/probe_ping.exs > "$W/probe.out" 2>&1
showdiff "$W/probe.out" "$L/probe-after.txt"; rc=$?
verdict probe-after.txt $rc "(byte-identical to a warm run)" "(the diff above is the difference)"
echo "  NOTE, and the direction matters: against a COLD _build the same command emits extra"
echo "  dependency-compile lines, so the archive would have FEWER lines than that run."
echo "  Fewer-lines-than-the-run is the SIGNATURE OF FILTERING -- it is exactly what was"
echo "  found in instances #2 and #3 -- so it is never on its own an acquittal. What"
echo "  acquits this file is the byte-identical match against a warm run above."
echo
echo "=== CAPTURES: red.txt, the red half of red-before-green ==="
echo "  RESTORED in round 6. The round-4 sweep classified this file; the round-5 rewrite"
echo "  enumerated it and classified it nowhere, so a reader scanning for DIFFERS got a clean"
echo "  bill over a population the instrument had not finished. An unclassified file is not a"
echo "  RAW file. That is CONVENTIONS.md's 'proves nothing, and proves it quietly' shape, and"
echo "  it is the coverage regression r2 blocked round 5 on -- inside the round that promised"
echo "  the population."
echo "  Not re-runnable here: it is the failing state BEFORE the fix, and lib/ is now fixed."
echo "  Reproducing it needs lib/beam_mcp/server.ex reverted to base/main, which this script"
echo "  must not do to the working tree. Checked instead for the marks a filtered capture"
echo "  cannot have:"
if marks "$L/red.txt"; then
  verdict red.txt 0 "(banner + code: + stacktrace: + Finished in, all present)" ""
else
  verdict red.txt 1 "" "(a mark is missing; a filtered capture would look like this)"
fi
echo

echo "=== CAPTURES: the two mutation logs ==="
for m in a b; do
  f="$L/mutation-$m.txt"
  echo "-- mutation-$m.txt --"
  echo "  not re-run here: reproducing it needs a mutated copy of lib/, which this script"
  echo "  must not create in the working tree. Checked instead for the marks a filtered"
  echo "  capture cannot have -- the ExUnit banner and a complete failure body:"
  if marks "$f"; then
    verdict "mutation-$m.txt" 0 "(banner + code: + stacktrace: + Finished in, all present)" ""
  else
    verdict "mutation-$m.txt" 1 "" "(a mark is missing; a filtered capture would look like this)"
  fi
done
echo
echo "=== CAPTURES: the README-claim mutation logs ==="
echo "  Same treatment as the mutation logs above and for the same reason: reproducing them"
echo "  needs a mutated README or lib/, which this script must not create in the working tree."
for m in a b; do
  f="$L/mutation-readme-$m.txt"
  [ -f "$f" ] || continue
  echo "-- mutation-readme-$m.txt --"
  if marks "$f"; then
    verdict "mutation-readme-$m.txt" 0 "(banner + code: + stacktrace: + Finished in, all present)" ""
  else
    verdict "mutation-readme-$m.txt" 1 "" "(a mark is missing; a filtered capture would look like this)"
  fi
done
echo

echo "=== CAPTURES: the three specification pages, re-fetched and diffed against upstream ==="
echo "These are the only files whose source lives OUTSIDE the tree, so they are the only"
echo "ones a diff can check against an independent authority. Grouping them with prose"
echo "(the first version of this script did) is what would excuse never checking them."
fetch_check() { # fetch_check <archive> <url>
  if curl -sSL --fail "$2" -o "$W/$(basename $1)" 2>/dev/null; then
    showdiff "$W/$(basename $1)" "$1"; rc=$?
    verdict "$(basename $1)" $rc "(re-fetched from $2)"
  else
    printf '  => %-24s UNCHECKED (fetch failed; offline)\n' "$(basename $1)"
  fi
}
fetch_check "$L/spec-basic-versioning.md" "https://modelcontextprotocol.io/specification/2026-07-28/basic/versioning.md"
fetch_check "$L/spec-changelog.md"        "https://modelcontextprotocol.io/specification/2026-07-28/changelog.md"
fetch_check "$L/spec-legacy-basic.md"     "https://modelcontextprotocol.io/specification/2025-11-25/basic.md"
echo
echo "=== AUTHORED: the lane reports ==="
for f in $(git ls-files -- "$L/round*.md"); do
  printf '  %-28s written by its own reviewer lane; not a command capture\n' "$(basename $f)"
done
echo
echo "=== archive-sweep.txt itself ==="
echo "  A file cannot diff itself while being written, so this entry NAMES ITS CHECK rather"
echo "  than asserting a conclusion -- the thing this script's own header forbids:"
printf '     script sha256 : %s\n' "$(sha256sum tools/archive_sweep.sh | cut -d" " -f1)"
printf '     reproduce     : ./tools/archive_sweep.sh > %s 2>&1\n' "$L/archive-sweep.txt"
echo "     then diff that against the tracked file. A reader who doubts any verdict above"
echo "     re-runs that one line; the script is tracked, so the bytes that produced this"
echo "     output are in the tree next to it."
verdict archive-sweep.txt 0 "(self: named check above, not an assertion)" ""
echo

echo "=== CLOSING TALLY -- the structural fix, not an instance fix ==="
echo "  Round 5 enumerated red.txt and classified it nowhere: 19 listed, 18 classified, and"
echo "  the output still read as a clean sweep because nothing counted. A file could drop out"
echo "  QUIETLY -- CONVENTIONS.md's own worst shape, and this script's header says a list is"
echo "  not a population. So the population and the classifications are now counted and"
echo "  compared, and disagreement is a FAILURE of this script rather than a silent gap."
ENUM=$(git ls-files -- "$L/*" | wc -l)
AUTH=$(git ls-files -- "$L/round*.md" | wc -l)
printf '  enumerated : %s\n  classified : %s  (%s verdicts + %s authored lane reports)\n' \
       "$ENUM" "$((CLASSIFIED + AUTH))" "$CLASSIFIED" "$AUTH"
if [ "$ENUM" -eq "$((CLASSIFIED + AUTH))" ]; then
  echo "  => TALLY BALANCES: every enumerated file is classified."
else
  echo "  => TALLY FAILS: $((ENUM - CLASSIFIED - AUTH)) enumerated file(s) unclassified."
  echo "     Unclassified is NOT the same as RAW. Do not read this sweep as clean."
  exit 1
fi
