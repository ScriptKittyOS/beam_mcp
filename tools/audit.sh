#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# The dependency audit: no retired package and no package with a security advisory ships.
#
#     tools/audit.sh            (from a project's root; the gate calls it; the probe calls it
#                                inside a planted consumer)
#
# Runs `mix hex.audit` -- built into Hex, no dependency of this package -- and prints ONE line,
# with an exit code that says which of three things happened:
#
#     0   measured, clean:   "audit ok: N locked packages, none retired, no advisory (M ignored)"
#     1   measured, not clean: hex's own output follows the line, verbatim
#     2   NOT MEASURED:      the registry could not be reached and hex answered from its cache
#
# THE THIRD IS THE REASON THIS SCRIPT EXISTS. With the registry unreachable, `mix hex.audit`
# prints "Failed to fetch record for <pkg> from registry (using cache instead)" per package,
# then "No retired or security advisory packages found", and EXITS 0 -- a pass from stale
# data (measured 2026-09-17 with HEX_MIRROR pointed at a closed port). An audit that read
# yesterday's registry is not an audit of today's advisories, so those lines are read and the
# result is refused as a measurement, whatever the exit code says. The gate decides what a
# non-measurement costs: locally it is said and not failed (a contributor offline is not
# wrong), in CI it fails (GATE_AUDIT=require), because CI is the seat that can always reach
# the registry and the one place a stale pass would be mistaken for a fresh one.
#
# The advisory feed hex reads is OSV's (each advisory carries `api.osv.dev/v1/vulns/<id>`,
# with CVE and GHSA aliases; the EEF CNA's ids), so this one call is the OSV audit too --
# a second scanner would add a dependency and no source (measured on hex.pm's package API).
#
# The population is the lock file's, which is what hex audits: N is counted from mix.lock so
# the line says how many packages the verdict is about. Advisories a project has chosen to
# ignore (`hex: [audit: [ignore: ...]]` in mix.exs) are counted and printed with the pass, so
# a pass over an ignore is never a silent one.
set -uo pipefail
out=$(mix hex.audit 2>&1); rc=$?
n_locked=$(grep -cE '^  "[a-z_0-9]+": \{' mix.lock 2>/dev/null || echo 0)
n_ignored=$(grep -A20 'hex:' mix.exs 2>/dev/null | grep -cE '^\s*(ignore|"[A-Z]+-[A-Za-z0-9-]+")' || true)
stale=$(printf '%s\n' "$out" | grep -c 'using cache instead' || true)
if [ "$stale" -gt 0 ]; then
  echo "audit NOT MEASURED: the registry could not be reached; hex answered for $stale package(s) from its cache and would have said pass"
  printf '%s\n' "$out" | grep -E 'failed_connect|Failed to fetch' | head -3
  exit 2
fi
if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q '^No retired or security advisory packages found'; then
  echo "audit ok: $n_locked locked packages, none retired, no advisory ($n_ignored ignored)"
  exit 0
fi
if printf '%s\n' "$out" | grep -qE '^Found (retired packages|packages with security advisories)'; then
  echo "audit FAIL: $(printf '%s\n' "$out" | grep -E '^Found' | tr '\n' ';')"
  printf '%s\n' "$out"
  exit 1
fi
echo "audit FAIL: hex.audit exit $rc with output this script does not recognise"
printf '%s\n' "$out"
exit 1
