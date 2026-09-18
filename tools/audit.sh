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
#     2   NOT MEASURED:      hex answered without reaching the registry
#
# THE THIRD IS THE REASON THIS SCRIPT EXISTS, and it has two doors. (1) With the registry
# unreachable, `mix hex.audit` prints "Failed to fetch record for <pkg> from registry (using
# cache instead)" per package, then "No retired or security advisory packages found", and
# EXITS 0 (measured 2026-09-17 with HEX_MIRROR at a closed port). In Hex 2.5.1 that suffix is
# printed on every fetch failure whether or not anything is cached -- so it is a pass from no
# data as often as from stale data -- and "Failed to fetch record" is read here with or without
# the suffix, in case Hex ever stops adding it. (2) Hex's own OFFLINE MODE -- `HEX_OFFLINE=1`, or
# `offline: true` in the global hex config or in mix.exs's `hex:` -- never touches HTTP and
# prints NOTHING when every package is cached; a review lane measured "No retired or security
# advisory packages found", exit 0, under it. So this script FORCES online mode: `HEX_OFFLINE=0`
# wins over both config sources in Hex (state.ex), and a machine that truly cannot reach the
# registry then takes door (1) and is refused as a measurement. The gate decides what a
# non-measurement costs: locally it is said and not failed (a contributor offline is not
# wrong), in CI it fails (GATE_AUDIT=require), because CI is the seat that can always reach
# the registry and the one place a stale pass would be mistaken for a fresh one.
#
# The advisory feed hex reads is OSV's (each advisory carries `api.osv.dev/v1/vulns/<id>`,
# with CVE and GHSA aliases; the EEF CNA's ids), so this one call is the OSV audit too --
# a second scanner would add a dependency and no source (measured on hex.pm's package API).
#
# IGNORES ARE READ FROM HEX'S OUTPUT, NOT FROM mix.exs. A project can ignore findings by
# `hex: [ignore_advisories: [...], ignore_retirements: [...]]` in mix.exs, by the global
# config, or by HEX_IGNORE_ADVISORIES / HEX_IGNORE_RETIREMENTS; hex then prints them under
# "Ignored retired:" / "Ignored advisories:" INSTEAD of the "No retired ..." line, still exit 0.
# A clean run with ignores is a pass here, with the count on the line and hex's ignored
# sections printed after it, so a pass over an ignore is never a silent one. The count is
# hex's -- the entries it listed as ignored -- not a grep of mix.exs (a first cut grepped for
# a key that does not exist and would have read "0 ignored" over a real one).
#
# N is the lock file's `{:hex, ...}` entries -- the population hex audits (git and path
# dependencies are not hex's to audit and are not counted).
set -uo pipefail
out=$(HEX_OFFLINE=0 mix hex.audit 2>&1); rc=$?
n_locked=$(grep -cE '^  "[a-z_0-9]+": \{:hex, ' mix.lock 2>/dev/null); n_locked=${n_locked:-0}
unreached=$(printf '%s\n' "$out" | grep -c 'Failed to fetch record' || true)
if [ "$unreached" -gt 0 ]; then
  echo "audit NOT MEASURED: hex answered without reaching the registry for $unreached package(s) (it would have said pass)"
  printf '%s\n' "$out" | grep -E 'failed_connect|Failed to fetch' | head -3
  exit 2
fi
found=$(printf '%s\n' "$out" | grep -cE '^Found (retired packages|packages with security advisories)$' || true)
if [ "$rc" -eq 0 ] && [ "$found" -eq 0 ]; then
  if printf '%s\n' "$out" | grep -q '^No retired or security advisory packages found'; then
    echo "audit ok: $n_locked locked packages, none retired, no advisory (0 ignored)"
    # An ignore that matches nothing any more is hex's warning, and the gate is where a
    # contributor would see it (G-071): printed after the pass line, never a failure.
    printf '%s\n' "$out" | grep 'can be removed' | sed 's/\x1b\[[0-9;]*m//g' | sed 's/^/  stale ignore: /'
    exit 0
  fi
  if printf '%s\n' "$out" | grep -qE '^Ignored (retired|advisories):'; then
    # Hex lists each ignored finding as an indented "  <package> <version> - ..." line under
    # its section, entries separated by blank lines; on a clean run everything from the first
    # "Ignored" header to the end is ignored content, and nothing else is indented that way.
    n_ignored=$(printf '%s\n' "$out" | sed -n '/^Ignored \(retired\|advisories\):/,$p' | grep -cE '^  [a-z_0-9]+ [0-9][^ ]* - ' || true)
    echo "audit ok: $n_locked locked packages, none retired, no advisory ($n_ignored ignored -- hex's sections follow)"
    printf '%s\n' "$out" | sed -n '/^Ignored /,$p' | grep -v 'can be removed'
    printf '%s\n' "$out" | grep 'can be removed' | sed 's/\x1b\[[0-9;]*m//g' | sed 's/^/  stale ignore: /'
    exit 0
  fi
fi
if [ "$found" -gt 0 ]; then
  echo "audit FAIL: $(printf '%s\n' "$out" | grep -E '^Found' | tr '\n' ';')"
  printf '%s\n' "$out"
  exit 1
fi
echo "audit FAIL: hex.audit exit $rc with output this script does not recognise"
printf '%s\n' "$out"
exit 1
