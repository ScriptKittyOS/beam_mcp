#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Probe: does tools/flake_hunt.sh give every run a seed of its own and pass it to `mix test`,
# fail the hunt on one red run among greens and name that run's tests with the command that
# replays it, count a run that printed no summary as failed (a green exit with nothing
# measured is not a pass), and refuse a run count that is not a positive integer -- with a
# fake `mix` on PATH that answers a scripted sequence of runs? The suite is never run; the
# probe is offline and takes a second.
#
#     tools/probe_flake_hunt.sh
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/beam_mcp-probe-hunt.XXXXXX"); trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"
# The fake mix: records its arguments, then plays the outcome named on the counter's line of
# $PROBE_SCRIPT (pass, fail or silent), holding the last line.
cat > "$work/bin/mix" <<'MIX'
#!/usr/bin/env bash
n=$(cat "$PROBE_DIR/n"); echo $((n + 1)) > "$PROBE_DIR/n"
echo "$*" >> "$PROBE_DIR/argv"
outcome=$(sed -n "$((n + 1))p" "$PROBE_SCRIPT"); [ -n "$outcome" ] || outcome=$(tail -1 "$PROBE_SCRIPT")
case $outcome in
  pass) printf 'Finished in 1.0 seconds\n11 properties, 786 tests, 0 failures\n'; exit 0 ;;
  fail) printf '  1) test the restarted collector counts from no rows (BeamMCP.ObservedTest)\n     test/beam_mcp/connectome/observed_test.exs:150\n\nFinished in 1.0 seconds\n11 properties, 786 tests, 1 failure\n'; exit 2 ;;
  silent) exit 0 ;;
  # Elixir 1.20's summary (measured on 1.20.4): "Result: N passed (...)" green, "Result: P/T passed" red.
  pass120) printf 'Finished in 1.0 seconds (0.5s async, 0.5s sync)\n\nResult: 798 passed (11 properties, 787 tests)\n'; exit 0 ;;
  fail120) printf '  1) test the restarted collector counts from no rows (BeamMCP.ObservedTest)\n     test/beam_mcp/connectome/observed_test.exs:150\n\nFinished in 1.0 seconds\n\nResult: 797/798 passed\n'; exit 2 ;;
esac
MIX
chmod +x "$work/bin/mix"
bad=0
run() { # run <case> <want exit> <outcomes, space separated> <runs> [<grep the output must match>...]
  local name=$1 want=$2 outcomes=$3 runs=$4; shift 4
  d=$work/$(echo "$name" | cut -d' ' -f1); mkdir -p "$d"; echo 0 > "$d/n"; : > "$d/argv"
  printf '%s\n' $outcomes > "$d/script"
  out=$(PATH="$work/bin:$PATH" PROBE_DIR=$d PROBE_SCRIPT=$d/script FLAKE_HUNT_SEED_BASE=1000 \
    bash "$here/tools/flake_hunt.sh" "$runs" "$d/out" 2>&1); rc=$?
  ok=1; [ "$rc" -eq "$want" ] || ok=0
  for pattern in "$@"; do printf '%s\n' "$out" | cat - "$d/argv" | grep -qE -- "$pattern" || { ok=0; echo "    missing: $pattern"; }; done
  printf '  %-58s exit %s (want %s)%s\n' "$name" "$rc" "$want" "$([ $ok -eq 1 ] || echo '  <-- WRONG')"
  [ $ok -eq 1 ] || bad=1
}
run "H1 three green runs" 0 "pass" 3 "hunt: 3 run\(s\), 0 failed"
run "H2 each run its own seed, passed to mix test" 0 "pass" 3 "^test --seed 1001$" "^test --seed 1002$" "^test --seed 1003$"
run "H3 one red run among greens" 1 "pass fail pass" 3 "run 2: seed 1002; exit 2" "the restarted collector counts from no rows" "mix test --seed 1002" "hunt: 3 run\(s\), 1 failed"
run "H4 a green exit with no summary is not a pass" 1 "silent" 1 "no summary" "hunt: 1 run\(s\), 1 failed"
run "H5 a run count that is not a positive integer" 2 "pass" 0
run "H6 the red run's whole output is kept" 1 "fail" 1
run "H7 Elixir 1.20's green summary is a summary" 0 "pass120" 2 "run 1: seed 1001; exit 0; Result: 798 passed" "hunt: 2 run\(s\), 0 failed"
run "H8 Elixir 1.20's red run is named with its replay" 1 "pass120 fail120" 2 "run 2: seed 1002; exit 2; Result: 797/798 passed" "the restarted collector" "mix test --seed 1002"
ls "$work/H6/out"/run-1-seed-1001.txt >/dev/null 2>&1 || { echo "    missing: H6's kept output"; bad=1; }
if [ "$bad" -eq 0 ]; then echo "PROBE OK: every run has its own seed; a red or silent run fails the hunt, named with its replay"; else echo "PROBE FAILED"; exit 1; fi
