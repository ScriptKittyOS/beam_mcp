#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
#     tools/probes/rate.sh <out-file> <n> <max-cases> [load]
#
# Runs the suite <n> times and records how many runs exited non-zero, whole, with the failing
# test named in each. THE RED FOR AN INTERMITTENT DEFECT IS A RATE, NOT A TRANSCRIPT: a single
# passing run is not evidence and a single failing one is not a measurement.
#
# Output is never filtered through grep on the way to the archive. CONVENTIONS.md: a verbatim
# archive is written by a command that fetches it, or it does not exist.
set -u
cd "$(git rev-parse --show-toplevel)" || exit 1
out="$1"; n="$2"; mc="$3"; load="${4:-0}"
{
  echo "== $(basename "$out" .txt) =="
  echo "command: mix test --max-cases $mc   (x$n consecutive runs)"
  echo "background load: $load concurrent cpu hogs"
  echo "host: $(uname -sr)  cores=$(nproc 2>/dev/null || sysctl -n hw.ncpu)"
  echo "tree: $(git rev-parse HEAD)  dirty=$(git status --porcelain | wc -l)"
  echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
} > "$out"
pids=()
if [ "$load" -gt 0 ]; then
  for _ in $(seq 1 "$load"); do ( while :; do :; done ) & pids+=($!); done
fi
fails=0
for i in $(seq 1 "$n"); do
  echo "---- run $i ----" >> "$out"
  o=$(mix test --max-cases "$mc" 2>&1); rc=$?
  printf '%s\n' "$o" >> "$out"
  echo "RUN_EXIT=$rc" >> "$out"
  [ "$rc" -ne 0 ] && fails=$((fails + 1))
done
for p in ${pids[@]+"${pids[@]}"}; do kill "$p" 2>/dev/null; done
{ echo; echo "== $(basename "$out" .txt): $fails run(s) of $n exited non-zero =="; } >> "$out"
echo "$(basename "$out" .txt): $fails/$n non-zero"
