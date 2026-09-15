<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# The conformance harness

Runs the official MCP conformance suite (`@modelcontextprotocol/conformance`, pinned by exact
version in `tools/conformance.sh`) against this package's HTTP transport and publishes two rows
per revision, derived from the suite's own `checks.json` and never typed:

- **suite totals** — scored scenarios passed / scored, over the revision's frozen requirement
  set; the failures are not hidden.
- **claimed-surface totals** — the same, over only the scenarios whose methods and tool names
  this package says it implements; a reader does not conclude the package fails what it never
  claimed. The set, by name (`CLAIMED` in `tools/conformance.sh`): `server-stateless`
  (`server/discover` and the stateless rules), `tools-list`, `tools-call-simple-text`,
  `tools-call-error` (`tools/call` with text content and tool errors),
  `dns-rebinding-protection` (the origin rules) and `server-sse-multiple-streams` (concurrent
  POSTs, JSON responses allowed). The two `input-required-result-*` scenarios that pass are
  not in it: they pass vacuously, on an unknown tool.

**The rule the rows use** is the suite's own under `--expected-failures`: a scenario passes
when none of its checks is `FAILURE` or `WARNING`; `SKIPPED` and `INFO` do not fail it. The
suite's plain console summary ticks a WARNING-only scenario; the baseline verdict — the one
that can exit 1 — does not, so a hand count of the console's scored ticks reads two higher
(14 / 37 on 2026-09-15, the day the five resource scenarios passed) than the rows. The rows
follow the verdict.

`baseline-<revision>.yml` lists every expected failure with a reason word in the comment beside
it — `deliberately-out`, `decided-not-built`, `not-implemented`, `harness` (the suite needs a
diagnostic tool this package cannot honestly serve), `design` (the legacy revision over HTTP:
the transport serves `2026-07-28` only, and `2025-11-25` lives on stdio, which the suite cannot
drive). The suite exits 1 on an unexpected failure AND on a baselined scenario that now passes,
so a fix cannot hide behind an old excuse and a regression cannot hide behind a pass rate.

    tools/conformance.sh            # both revisions; needs Node >= 22 and the npx cache
