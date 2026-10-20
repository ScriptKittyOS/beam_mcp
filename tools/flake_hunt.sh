#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# The suite, run many times to find a test that fails only sometimes. A flaky test shows on one
# run in tens: the three found so far each failed one CI leg once, passed on that leg's rerun,
# and passed alone, so a single green run says nothing about them. This runs `mix test` <runs>
# times, each in a fresh VM (not `--repeat-until-failure`, which reruns in one VM, where state
# one run leaves can fail the next for a reason that is not the test's), each with a seed of
# its own: ExUnit does not print the seed it chose, and a failure that cannot be replayed
# cannot be fixed. A red run prints its failed tests and the command that replays it, and its
# whole output is kept; a green run's is dropped. ERL_FLAGS passes through to every run, so
# `ERL_FLAGS="+S 2"` hunts with two schedulers.
#
#     tools/flake_hunt.sh <runs> [<out-dir>]
# env: FLAKE_HUNT_SEED_BASE (default: the clock); run i uses seed base + i.
# exit 0: every run green; 1: a run red, or a run that printed no summary; 2: usage.
set -uo pipefail
runs=${1:-}
case $runs in '' | *[!0-9]* | 0) echo "usage: tools/flake_hunt.sh <runs> [<out-dir>] (runs: a positive integer, got '$runs')" >&2; exit 2 ;; esac
out=${2:-${TMPDIR:-/tmp}/beam_mcp-flake-hunt}
mkdir -p "$out"
base=${FLAKE_HUNT_SEED_BASE:-$(($(date +%s) % 1000000))}
failed=0
for i in $(seq 1 "$runs"); do
  seed=$((base + i))
  log="$out/run-$i-seed-$seed.txt"
  mix test --seed "$seed" > "$log" 2>&1
  rc=$?
  # The summary line in either of ExUnit's forms: "786 tests, 0 failures" (to Elixir 1.19) or
  # "Result: 798 passed (...)", "Result: 797/798 passed" (1.20 on).
  summary=$(grep -E '[0-9]+ tests?, [0-9]+ failures?|^Result: [0-9]+(/[0-9]+)? passed' "$log" | tail -1)
  echo "run $i: seed $seed; exit $rc; ${summary:-no summary}"
  # A green exit with no summary measured nothing (the suite did not report), so it is not a pass.
  if [ "$rc" -ne 0 ] || [ -z "$summary" ]; then
    failed=$((failed + 1))
    grep -E '^ +[0-9]+\) (test|property|doctest) ' "$log" | sed -E 's/^ +/    /'
    echo "    replay: ERL_FLAGS='${ERL_FLAGS:-}' mix test --seed $seed   (output: $log)"
  else
    rm -f "$log"
  fi
done
echo "hunt: $runs run(s), $failed failed; ERL_FLAGS='${ERL_FLAGS:-}'"
[ "$failed" -eq 0 ]
