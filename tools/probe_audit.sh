#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Probe: does tools/audit.sh go red on a retired, advisoried dependency -- and refuse a pass
# from hex's cache -- or does it pass over both?
#
# The population is derived the way the mechanism derives it: a project's own mix.lock, read
# by `mix hex.audit` in that project. So the plant is a throwaway consumer OUTSIDE this tree
# whose one dependency is `plug 1.20.0` -- retired on hex.pm ("invalid: Accidental breaking
# change on Plug.Conn.inform") and inside two advisories' ranges (EEF-CVE-2026-56813,
# EEF-CVE-2026-56814; measured 2026-09-17) -- and the same script is run there. A second run
# points HEX_MIRROR at a closed port, which is how the cache-pass was found. Nothing in this
# tree is touched. Network: the first run needs hex.pm; without it the probe says so and
# exits 2, never "pass".
#
#     tools/probe_audit.sh
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/beam_mcp-probe-audit.XXXXXX"); trap 'rm -rf "$work"' EXIT
cat > "$work/mix.exs" <<'MIX'
defmodule ProbeAudit.MixProject do
  use Mix.Project
  def project, do: [app: :probe_audit, version: "0.1.0", elixir: "~> 1.17", deps: [{:plug, "1.20.0"}]]
  def application, do: []
end
MIX
cd "$work" || exit 1
if ! mix deps.get >"$work/deps.get.out" 2>&1; then
  echo "PROBE NOT MEASURED: mix deps.get failed in the throwaway consumer (no registry?)"
  tail -3 "$work/deps.get.out"; exit 2
fi
out=$(bash "$here/tools/audit.sh" 2>&1); rc=$?
printf '  planted plug 1.20.0: exit %s; first line: %s\n' "$rc" "$(printf '%s\n' "$out" | head -1)"
if [ "$rc" -ne 1 ] || ! printf '%s\n' "$out" | grep -q '^Retired:' || ! printf '%s\n' "$out" | grep -q '^Advisories:'; then
  echo "PROBE FAIL: expected exit 1 with a Retired: and an Advisories: section"; printf '%s\n' "$out"; exit 1
fi
out2=$(HEX_MIRROR=http://127.0.0.1:9 HEX_HTTP_TIMEOUT=5 bash "$here/tools/audit.sh" 2>&1); rc2=$?
printf '  registry closed:     exit %s; first line: %s\n' "$rc2" "$(printf '%s\n' "$out2" | head -1)"
if [ "$rc2" -ne 2 ]; then
  echo "PROBE FAIL: a pass from the cache was not refused (expected exit 2)"; printf '%s\n' "$out2"; exit 1
fi
echo "PROBE OK: the retired, advisoried plant reads FAIL; the cache answer reads NOT MEASURED"
