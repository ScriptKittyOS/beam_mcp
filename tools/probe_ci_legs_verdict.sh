#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Probe: does tools/ci_legs_verdict.sh wait for legs still running and then judge them, fail a
# red leg, fail too few legs, and fail at its bound -- with a fake `gh` on PATH that answers a
# scripted sequence of check-run pages (G-079's in_progress-then-success case first)? Nothing
# reaches GitHub; the probe is offline.
#
#     tools/probe_ci_legs_verdict.sh
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/beam_mcp-probe-legs.XXXXXX"); trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
# The fake gh: prints the JSON page named by a counter file, advancing one per call, holding
# the last. It ignores --jq and applies the real jq filter itself, so the script's filter is
# the one exercised.
cat > "$work/bin/gh" <<'GH'
#!/usr/bin/env bash
seq_dir=$PROBE_SEQ; n=$(cat "$seq_dir/n"); pages=$(ls "$seq_dir"/page.* | wc -l)
[ "$n" -lt "$pages" ] && echo $((n + 1)) > "$seq_dir/n"
page="$seq_dir/page.$n"; [ -f "$page" ] || page="$seq_dir/page.$((pages - 1))"
filter=""; while [ $# -gt 0 ]; do [ "$1" = "--jq" ] && filter=$2; shift; done
grep -q '"__fail__"' "$page" && { echo "gh: HTTP 502 (fake)" >&2; exit 1; }
jq -r "$filter" < "$page"
GH
chmod +x "$work/bin/gh"
command -v jq >/dev/null || { echo "PROBE NOT MEASURED: jq is not installed"; exit 2; }
leg() { printf '{"name":"Gate - leg (OTP %s, Elixir %s, %s)","status":"%s","conclusion":%s}' "$1" "$2" "$3" "$4" "$5"; }
page() { printf '{"check_runs":[%s]}' "$(IFS=,; echo "$*")"; }
skipped='{"name":"Gate - leg (OTP ${{ matrix.otp }}, Elixir ${{ matrix.elixir }}, ${{ matrix.leg }})","status":"completed","conclusion":"skipped"}'
bad=0
run() { # run <case> <want> <seqdir>
  echo 0 > "$3/n"
  out=$(PATH="$work/bin:$PATH" PROBE_SEQ=$3 POLL_SECONDS=0 POLL_LIMIT=3 bash "$here/tools/ci_legs_verdict.sh" o/r deadbeef 2>&1); rc=$?
  printf '  %-52s exit %s (want %s); pages advanced %s; last: %s\n' "$1" "$rc" "$2" "$(cat "$3/n")" "$(printf '%s\n' "$out" | tail -1 | cut -c1-60)"
  [ "$rc" -eq "$2" ] || bad=1
}
# S1: G-079 -- two polls in progress (conclusion null), then all success.
d=$work/s1; mkdir -p "$d"
page "$(leg 27 1.17 floor in_progress null)" "$(leg 28 1.18 pinned in_progress null)" "$(leg 29 1.20 head completed '"success"')" "$skipped" > "$d/page.0"
page "$(leg 27 1.17 floor completed '"success"')" "$(leg 28 1.18 pinned in_progress null)" "$(leg 29 1.20 head completed '"success"')" "$skipped" > "$d/page.1"
page "$(leg 27 1.17 floor completed '"success"')" "$(leg 28 1.18 pinned completed '"success"')" "$(leg 29 1.20 head completed '"success"')" "$skipped" > "$d/page.2"
run "S1 in_progress twice, then three successes" 0 "$d"
# S2: a leg red once complete.
d=$work/s2; mkdir -p "$d"
page "$(leg 27 1.17 floor in_progress null)" "$(leg 28 1.18 pinned completed '"success"')" "$(leg 29 1.20 head completed '"success"')" > "$d/page.0"
page "$(leg 27 1.17 floor completed '"failure"')" "$(leg 28 1.18 pinned completed '"success"')" "$(leg 29 1.20 head completed '"success"')" > "$d/page.1"
run "S2 a leg completes as failure" 1 "$d"
# S3: a leg never completes -- the bound.
d=$work/s3; mkdir -p "$d"
page "$(leg 27 1.17 floor in_progress null)" "$(leg 28 1.18 pinned completed '"success"')" "$(leg 29 1.20 head completed '"success"')" > "$d/page.0"
run "S3 a leg never completes (bound of 3 polls)" 1 "$d"
# S4: only two legs exist, both green -- the tree is unmeasured on one pair.
d=$work/s4; mkdir -p "$d"
page "$(leg 28 1.18 pinned completed '"success"')" "$(leg 29 1.20 head completed '"success"')" "$skipped" > "$d/page.0"
run "S4 two legs only, the skipped unexpanded name beside" 1 "$d"
# S5: all three complete and green on the first read -- no wait.
d=$work/s5; mkdir -p "$d"
cp "$work/s1/page.2" "$d/page.0"
run "S5 three successes on the first read" 0 "$d"
# S6: the API fails once, then three successes -- a read spent, not a verdict.
d=$work/s6; mkdir -p "$d"
echo '{"__fail__":true}' > "$d/page.0"; cp "$work/s1/page.2" "$d/page.1"
run "S6 the API fails once, then three successes" 0 "$d"
# S7: the API fails every time -- the bound, named as a failed read.
d=$work/s7; mkdir -p "$d"
echo '{"__fail__":true}' > "$d/page.0"
run "S7 the API fails every time (bound)" 1 "$d"
# S8: an empty page -- no check runs at all; the count says 0, not 1.
d=$work/s8; mkdir -p "$d"
echo '{"check_runs":[]}' > "$d/page.0"
run "S8 no check runs at all" 1 "$d"
if [ "$bad" -eq 0 ]; then echo "PROBE OK: the read waits for running legs, then judges; red, too few, and the bound are FAIL"; else echo "PROBE FAILED"; exit 1; fi
