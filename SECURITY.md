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

This policy is a maintainer's commitment and claims no regulatory status: it does not assert
that the package, its author or its distribution meets any statutory scheme's definition of a
product, a manufacturer or a steward.

## Severity, in this package's terms

The assessment names one of four levels, by what a defect lets a client do to the host that
embeds this package — not by a generic score. The fix window is the intent stated at
assessment; the 30-day assessment window above is the commitment.

| level | what it means here | fix window (intent) |
|---|---|---|
| **Critical** | A client reaches dispatch with arguments the advertised schema forbids, or reaches a tool the catalog did not advertise, or crashes the host's server process with one message. | A patch release of the supported minor carrying only the fix, as soon as it can be cut. |
| **High** | A client is served under a protocol revision it did not declare, or reads server internals across the wire (a stack, a path, a secret in a fault), or desynchronises the reader so one message is read as another. | The next scheduled release, or sooner if a workaround cannot be stated. |
| **Medium** | A bound (line, body, nesting, connection) can be exceeded or evaded so the host buffers without limit, where a stated workaround exists (a transport option where one exists — the HTTP transport's timeouts — or a limit in front of the package). | A scheduled release; the workaround published at assessment. |
| **Low** | Wrong error codes or messages, a refusal that names more than it should, a documented behaviour the package does not quite match. | With other work; recorded in the changelog when fixed. |

The examples are this package's own surface (see *In scope*); a report about a host's tool or
an injected function is out of scope at any level.

## CVEs

Advisories are published from this repository's GitHub Security Advisories. GitHub is a CVE
Numbering Authority (CNA) for repositories it hosts, so a CVE is requested from the advisory
draft and assigned before publication when the defect warrants one — Critical and High always
do; Medium when a consumer needs an identifier to act on; Low rarely. A published advisory
reaches the GitHub Advisory Database and OSV, the source hex.pm's registry advisories are fed
from and `mix hex.audit` reads, so a consumer running the audit sees it against their lock
file without this project telling them.

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
| `0.5.x` | yes |
| `0.4.x` | no — superseded |
| `0.3.x` | no — superseded |
| `0.2.x` | no — superseded |
| `0.1.x` | no — superseded |

This table names what a single maintainer can actually keep. Read it with the acknowledgement
and assessment windows above, which are the commitments that matter more.
