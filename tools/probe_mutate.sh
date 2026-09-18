#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Probe: does tools/mutate.sh tell a compiler kill from a kill, and does a derived scope lose a
# kill that only an out-of-scope test makes?
#
# Two mutants, written by this probe into a scratch mutants directory (MUTANTS_DIR), never into
# tools/mutants: (1) Mck orphans a bound variable in the tracer, which under warnings_as_errors
# fails compilation -- the row must read COMPILER-KILL, not a kill, and not a survivor; (2) Mos
# narrows mix.exs's files: glob so lib/beam_mcp/connectome/*.ex no longer ships -- killed by the
# README files-list census (readme_claims_test) and by nothing that names BeamMCP.MixProject, so
# under SCOPE=derived it survives the scope and the harness must re-score it against all and
# read KILLED. The populations are derived the way the harness derives them (the same
# derive_tests, the same suite); the expectations are read off the rows, quoted.
#
#     tools/probe_mutate.sh
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1
[ -z "$(git status --porcelain -- lib mix.exs)" ] || { echo "PROBE REFUSED: lib/ or mix.exs is dirty"; exit 2; }
M=$(mktemp -d "${TMPDIR:-/tmp}/beam_mcp-probe-mutants.XXXXXX"); trap 'rm -rf "$M"' EXIT
cat > "$M/Mck.py" <<'PY'
import io, sys
p = sys.argv[1]; s = io.open(p, encoding="utf-8").read()
old = "  defp weight(w) when is_float(w), do: [:erlang.float_to_binary(w, [:short])]"
assert s.count(old) == 1, s.count(old)
# an unused variable under warnings_as_errors: the compile fails, no test runs
io.open(p, "w", encoding="utf-8").write(s.replace(old, "  defp weight(w) when is_float(w), do: (orphan = w; [:erlang.float_to_binary(w, [:short])])"))
PY
cat > "$M/Mos.py" <<'PY'
import io, sys
p = sys.argv[1]; s = io.open(p, encoding="utf-8").read()
old = "lib/**/*.ex docs/*.md"
assert s.count(old) == 1, s.count(old)
io.open(p, "w", encoding="utf-8").write(s.replace(old, "lib/beam_mcp/*.ex docs/*.md"))
PY
echo "--- (1) a compiler kill on lib/beam_mcp/connectome/canonical.ex:"
row=$(MUTANTS_DIR="$M" TARGET=lib/beam_mcp/connectome/canonical.ex PASSES=1 SCOPE=derived bash tools/mutate.sh score Mck 2>&1)
printf '%s\n' "$row" | grep -E '^Mck|^scope:' | cut -c1-140
printf '%s\n' "$row" | grep -q '^Mck | COMPILER-KILL -- not a kill' || { echo "PROBE FAIL: a compiler kill was not named as one"; exit 1; }
echo "--- (2) a kill only an out-of-scope test makes, on mix.exs under SCOPE=derived:"
row=$(MUTANTS_DIR="$M" TARGET=mix.exs PASSES=1 SCOPE=derived bash tools/mutate.sh score Mos 2>&1)
printf '%s\n' "$row" | grep -E '^Mos|^scope:|readme_claims' | cut -c1-160
printf '%s\n' "$row" | grep -q '^Mos | SURVIVED-IN-SCOPE -> all: KILLED' || { echo "PROBE FAIL: the scope's survivor was not re-scored to a kill"; exit 1; }
[ -z "$(git status --porcelain -- lib mix.exs)" ] || { echo "PROBE FAIL: the harness left lib/ or mix.exs dirty"; exit 1; }
echo "PROBE OK: a compiler kill reads COMPILER-KILL; a scope's survivor is re-scored against all and reads KILLED"
