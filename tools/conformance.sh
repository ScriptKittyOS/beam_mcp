#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# The conformance harness. Starts conformance/server.exs (the package's HTTP transport with the
# honest fixture catalog), runs the official suite's frozen requirement set for each revision
# the package targets against it, and prints TWO ROWS per revision, both derived from the
# suite's checks.json and never typed:
#
#   suite totals            scored scenarios passed / scored -- the failures are not hidden
#   claimed-surface totals  the same over the scenarios whose methods and tool names this
#                           package claims -- a reader does not conclude it fails what it
#                           never claimed
#
# The suite is pinned by EXACT version below; a bump is a dated commit that re-measures. The
# baseline files carry every expected failure with its reason word; the suite exits 1 on an
# unexpected failure and on a stale baseline entry, and so does this script.
#
#     tools/conformance.sh                (needs Node >= 22 and python3; the first run fetches the suite)
#
# THE RULE THE ROWS USE is the suite's own under --expected-failures: a scenario passes when
# none of its checks is FAILURE or WARNING (SKIPPED and INFO do not fail it). The suite's plain
# console summary marks a WARNING-only scenario with a tick; the baseline verdict does not, and
# the baseline verdict is the one that can exit 1, so it is the one the rows follow.
#
# Environment: PORT (default 4321), OUT (results directory, default a temp dir).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

SUITE="@modelcontextprotocol/conformance@0.2.0-alpha.11"
PORT="${PORT:-4321}"
OUT="${OUT:-$(mktemp -d)}"
mkdir -p "$OUT"
REVISIONS="2026-07-28 2025-11-25"
# The claimed surface, by scenario name: server/discover and the stateless rules, tools/list,
# tools/call with text content and tool errors, the HTTP header and origin rules.
CLAIMED="server-stateless tools-list tools-call-simple-text tools-call-error dns-rebinding-protection server-sse-multiple-streams"

if ! command -v node >/dev/null 2>&1 || [ "$(node -p 'process.versions.node.split(".")[0]')" -lt 22 ]; then
  echo "conformance FAIL: node >= 22 not found ($(node --version 2>/dev/null || echo none)); the suite needs it" >&2
  exit 2
fi
if ! command -v python3 >/dev/null 2>&1; then
  echo "conformance FAIL: python3 not found; the rows are derived from checks.json with it" >&2
  exit 2
fi

PORT="$PORT" mix run conformance/server.exs > "$OUT/server.log" 2>&1 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null; wait "$server_pid" 2>/dev/null' EXIT
for _ in $(seq 1 60); do
  grep -q "conformance server up" "$OUT/server.log" 2>/dev/null && break
  sleep 0.5
done
grep -q "conformance server up" "$OUT/server.log" || { echo "conformance FAIL: the server did not start"; cat "$OUT/server.log"; exit 2; }

status=0
for rev in $REVISIONS; do
  npx -y "$SUITE" server --url "http://127.0.0.1:$PORT/" --requirements "$rev" \
    --expected-failures "conformance/baseline-$rev.yml" -o "$OUT/$rev" > "$OUT/$rev.txt" 2>&1
  rc=$?
  # The rows, from checks.json: a scenario passes when none of its checks is FAILURE or WARNING.
  rows=$(python3 - "$OUT/$rev" "$SUITE" "$rev" "$CLAIMED" <<'PY'
import json, sys, glob, os, subprocess
out, suite, rev, claimed = sys.argv[1], sys.argv[2], sys.argv[3], set(sys.argv[4].split())
listing = subprocess.run(["npx", "-y", suite, "list", "--requirements", rev], capture_output=True, text=True).stdout
scored, section = [], None
for line in listing.splitlines():
    if line.startswith("Server scenarios"): section = "server"
    elif line.startswith("Client scenarios") or line.startswith("Run and reported"): section = None
    elif section == "server" and line.startswith("  - "): scored.append(line.strip()[2:])
def latest(name):
    # The suite writes a timestamped directory per run; with OUT reused, the newest is the run.
    ds = sorted(glob.glob(os.path.join(out, f"server-{name}-*")))
    return ds[-1] if ds else None
def checks_of(name):
    d = latest(name)
    return json.load(open(os.path.join(d, "checks.json"))) if d else None
def passed(name):
    checks = checks_of(name)
    if checks is None: return None
    # The suite's own rule under --expected-failures: a WARNING check fails the scenario too.
    return all(c.get("status") not in ("FAILURE", "WARNING") for c in checks)
suite_pass = sum(1 for s in scored if passed(s))
claimed_scored = [s for s in scored if s in claimed]
claimed_pass = sum(1 for s in claimed_scored if passed(s))
failing_claimed = [s for s in claimed_scored if not passed(s)]
detail = ""
for s in failing_claimed:
    checks = checks_of(s) or []
    ok = sum(1 for c in checks if c.get("status") == "SUCCESS")
    skipped = sum(1 for c in checks if c.get("status") == "SKIPPED")
    bad = sum(1 for c in checks if c.get("status") in ("FAILURE", "WARNING"))
    detail += f" ({s}: {ok} pass, {skipped} skipped, {bad} fail of {len(checks)} checks)"
print(f"conformance {rev}: suite {suite_pass}/{len(scored)} scored server scenarios; claimed surface {claimed_pass}/{len(claimed_scored)}{detail}")
PY
)
  if [ -z "$rows" ]; then
    echo "conformance FAIL: no rows derived for $rev (python3 or checks.json missing)"; status=1
  else
    echo "$rows (suite exit $rc)"
  fi
  [ "$rc" -eq 0 ] || status=1
done
echo "results: $OUT"
exit "$status"
