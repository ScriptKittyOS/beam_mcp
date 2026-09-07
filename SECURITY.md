<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Security Policy

## Reporting a vulnerability

Report privately through **[GitHub Security Advisories](https://github.com/ScriptKittyOS/beam_mcp/security/advisories/new)**.
Please do not open a public issue for a suspected vulnerability.

Useful in a report: the protocol revision and transport, a request that triggers it, what you
expected and what happened. A failing test is welcome and never required.

## What this project can commit to

This package is maintained by **one person**, and the commitment is written to be one that can
be kept rather than one that sounds reassuring:

- **Acknowledgement within 7 days.** If you have heard nothing after 7 days, assume the report
  did not arrive and open a public issue saying only that you are waiting on a security
  response — no detail.
- **An assessment within 30 days** of acknowledgement: whether it is in scope, and if so a
  rough severity and intended fix window. If it will take longer, you will be told that
  instead of being left waiting.
- **Credit in the advisory and the changelog**, unless you ask otherwise.

There is no paid bounty, and no guaranteed fix deadline. A single maintainer cannot honestly
promise a 24-hour turnaround, so this policy does not.

## In scope

The package's own code, `lib/`:

- **Protocol handling** — malformed, hostile or ambiguous JSON-RPC that crashes the server,
  bypasses validation, or is answered under the wrong protocol revision.
- **Framing and bounds** — input that escapes the line or body limits, or desynchronises the
  reader so one message is interpreted as another.
- **Schema validation** — arguments that reach dispatch despite violating the schema the
  catalog advertised, including key- or type-confusion between the validated form and the
  dispatched form.
- **Era confusion** — a request served under a protocol revision other than the one it
  declared.
- **Information disclosure across the wire boundary** — server internals reaching a client
  that should not see them.

## Out of scope

- **What a host's tools do.** This package validates and routes; it does not execute. A tool
  that deletes files when asked is the host's design, not a defect here.
- **Anything the host injects** — the catalog, the dispatch function, and whatever they reach.
- **Transport security.** stdio is a local pipe; confidentiality and authentication of that
  channel belong to whatever spawns the process.
- **Denial of service through legitimate volume.** Bounds exist to stop unbounded buffering,
  not to ration throughput.
- **Dependencies**, unless the defect is in how this package uses one. Report those upstream.

## Known, already public

Recorded so they are not reported as discoveries, and so their status is not mistaken for
ignorance of them:

- **The package is pre-1.0.** The API may still change between minor versions.

## Supported versions

Fixes land on the latest published minor. Earlier minors are not backported, and while the
package is `0.x` a fix may arrive in a release that also carries a wire change — the changelog
entry says so when it does.

| version | supported |
|---|---|
| `0.3.x` | yes |
| `0.2.x` | no — superseded |
| `0.1.x` | no — superseded |

This table names what a single maintainer can actually keep. Read it with the acknowledgement
and assessment windows above, which are the commitments that matter more.
