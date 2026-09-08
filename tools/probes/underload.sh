#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
#     tools/probes/underload.sh <load> <out-file> <command...>
#
# Runs a command with <load> busy loops alongside it and writes the whole output to <out-file>.
#
# WHY CPU STARVATION IS THE PROBE AND NOT A NUISANCE. The defect slice 006 fixed is governed by
# whether the client process is scheduled before a TCP reset lands. A 32-core development machine
# almost never loses that race; a two-core CI runner does. Deliberate oversubscription is how the
# development machine is made to answer the question CI was asking.
set -u
load="$1"; out="$2"; shift 2
pids=()
for _ in $(seq 1 "$load"); do ( while :; do :; done ) & pids+=($!); done
{
  echo "background load: $load busy loops on $(nproc 2>/dev/null || sysctl -n hw.ncpu) cores"
  echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "\$ $*"
  echo
  "$@" 2>&1
  echo "EXIT=$?"
} > "$out"
for p in "${pids[@]}"; do kill "$p" 2>/dev/null; done
tail -20 "$out"
