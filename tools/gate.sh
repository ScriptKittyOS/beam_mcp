#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# The quality gate. Every step reports its own verdict and its own exit code; a step that
# cannot measure something says so rather than passing. There are no ratchet baselines here:
# this tree starts clean and stays at zero, so a non-zero count is a failure, not a baseline.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

fail=0
note() { printf '  %-26s %s\n' "$1" "$2"; }
step() { # step <name> <command...>
  local name="$1"; shift
  local out rc
  out=$("$@" 2>&1); rc=$?
  if [ "$rc" -eq 0 ]; then note "$name" "pass"
  else note "$name" "FAIL (exit $rc)"; printf '%s\n' "$out" | sed 's/^/      /'; fail=1; fi
}

echo "== beam_mcp gate =="

step "format"   mix format --check-formatted
step "compile"  mix compile --warnings-as-errors --force
step "test"     mix test
step "credo"    mix credo --strict

# REUSE: every tracked file that can carry a comment carries an SPDX identifier.
# Derived from the tracked set, never from a hand list.
missing=$(git ls-files -- '*.ex' '*.exs' '*.sh' '*.yml' | while read -r f; do
  head -5 "$f" | grep -q 'SPDX-License-Identifier' || echo "$f"
done)
if [ -z "$missing" ]; then
  note "reuse" "pass ($(git ls-files -- '*.ex' '*.exs' '*.sh' '*.yml' | wc -l) commentable files)"
else
  note "reuse" "FAIL -- no SPDX-License-Identifier:"; printf '%s\n' "$missing" | sed 's/^/      /'; fail=1
fi

# The licence claim is only a claim until the files it names exist.
for f in LICENSE NOTICE LICENSES/Apache-2.0.txt; do
  [ -f "$f" ] || { note "licence files" "FAIL -- $f missing"; fail=1; }
done
[ "$fail" -eq 0 ] && note "licence files" "pass"

if [ "$fail" -eq 0 ]; then echo "Gate OK."; else echo "GATE FAILED."; fi
exit "$fail"
