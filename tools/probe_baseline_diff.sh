#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Probe: does tools/baseline_diff.sh go red on the two hand edits G-076 names -- a public
# entry's line deleted outright, and a marker arriving with a number the CHANGELOG already
# lists -- and stay green on the edits the writer and the release step make? Plants are on
# copies in a temp dir; the tree is not touched.
#
#     tools/probe_baseline_diff.sh
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/beam_mcp-probe-baseline.XXXXXX"); trap 'rm -rf "$work"' EXIT
cp "$here/docs/public-api.txt" "$work/base.txt"
cp "$here/CHANGELOG.md" "$work/changelog.md"
released=$(grep -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' "$work/changelog.md" | head -1 | tr -d '#[] ')
[ -n "$released" ] || { echo "PROBE NOT MEASURED: no released heading in CHANGELOG.md"; exit 2; }
entry=$(grep -v '^#' "$work/base.txt" | grep -m1 -v 'since=' || true)
[ -n "$entry" ] || { echo "PROBE NOT MEASURED: no unmarked entry in the baseline to plant on"; exit 2; }
bad=0
run() { # run <case> <expected exit> <head file>
  out=$(bash "$here/tools/baseline_diff.sh" "$work/base.txt" "$3" "$work/changelog.md" 2>&1); rc=$?
  printf '  %-58s exit %s (want %s): %s\n' "$1" "$rc" "$2" "$(printf '%s\n' "$out" | head -1 | cut -c1-70)"
  [ "$rc" -eq "$2" ] || bad=1
}
cp "$work/base.txt" "$work/same.txt";                                      run "P0 unchanged" 0 "$work/same.txt"
grep -vxF "$entry" "$work/base.txt" > "$work/deleted.txt";                run "P1 an entry's line deleted outright" 1 "$work/deleted.txt"
{ cat "$work/base.txt"; echo "$entry"; } | awk -v e="$entry" '$0==e && !s {print e" removed_in=Unreleased"; s=1; next} $0!=e' > "$work/marked.txt"
                                                                          run "P2 the same entry marked removed_in=Unreleased" 0 "$work/marked.txt"
sed "s|^$entry\$|$entry removed_in=$released|" "$work/base.txt" > "$work/backdated.txt"
                                                                          run "P3 removed_in= with the last release's number" 1 "$work/backdated.txt"
sed "s|^$entry\$|$entry deprecated_since=$released|" "$work/base.txt" > "$work/backdated2.txt"
                                                                          run "P4 deprecated_since= with the last release's number" 1 "$work/backdated2.txt"
sed "s|^$entry\$|$entry since=9.9.9|" "$work/base.txt" > "$work/release.txt"
                                                                          run "P5 a marker with a number not yet released (the release step)" 0 "$work/release.txt"
{ cat "$work/base.txt"; echo "BeamMCP.Probe function added/1 since=Unreleased"; } > "$work/added.txt"
                                                                          run "P6 a new entry marked Unreleased (the writer)" 0 "$work/added.txt"
{ cat "$work/base.txt"; echo "BeamMCP.Probe function added/1 since=$released"; } > "$work/added-backdated.txt"
                                                                          run "P7 a new entry marked since= the last release (back-dated addition)" 1 "$work/added-backdated.txt"
sed "s|^$entry\$|$entry removed_in=0.0.1|" "$work/base.txt" > "$work/phantom.txt"
                                                                          run "P8 removed_in= with a phantom number below the last release" 1 "$work/phantom.txt"
if [ "$bad" -eq 0 ]; then echo "PROBE OK: the two hand edits are red; the writer's and the release step's edits are green"; else echo "PROBE FAILED"; exit 1; fi
