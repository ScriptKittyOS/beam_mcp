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

# `optional: true` is a resolution flag, not a compilation one: the HTTP transport compiles here,
# where plug is present, and broke every stdio-only consumer until round 1. Asserted on the
# artefact in a throwaway consumer project, because a compile that "succeeded" is not evidence.
step "optional deps" bash tools/probe_optional_deps.sh

# `mix docs` EXITS 0 ON A WARNING, so its status is not a verdict and this step reads its output.
#
# A hidden module referenced by the docs shipped in 0.1.0 as `BeamMCP.Server`, and the CHANGELOG
# entry recording that also recorded why nothing caught it: "a hidden module is not a compile
# warning and the gate does not run `mix docs`". The gate then did not run mix docs for two more
# releases, and 0.3.0's first cut reproduced the defect on `BeamMCP.Transport.Stdio` -- the
# transport the README documents as the entry point. Fixing the instance twice and the mechanism
# never is what this step is for.
docs_out=$(mix docs 2>&1); docs_rc=$?
docs_warnings=$(printf '%s\n' "$docs_out" | grep -c 'warning:')
if [ "$docs_rc" -eq 0 ] && [ "$docs_warnings" -eq 0 ]; then
  note "docs" "pass"
else
  note "docs" "FAIL (exit $docs_rc, $docs_warnings warnings)"
  printf '%s\n' "$docs_out" | sed 's/^/      /'; fail=1
fi

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
