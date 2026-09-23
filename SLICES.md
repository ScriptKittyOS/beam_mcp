<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Slices

The work on this package is done in slices: each is a planned, reviewed unit of change that
lands through one pull request. The plans, review records and working notes behind them are
the team's and are kept outside this repository. What is public is what each slice committed,
below, and the detail of each change: its pull request, its commit messages, and the
CHANGELOG entry of the release it shipped in.

## 0.1.0 to 0.3.1: the protocol core and the HTTP transport

| slice | what it committed | pull request |
|---|---|---|
| 001 | Two protocol revisions supported and told apart (revision negotiation, `server/discover`); landed before pull requests were required | commit [36136a1](https://github.com/ScriptKittyOS/beam_mcp/commit/36136a1) |
| (before the numbering rule) | Errors carried across the wire as JSON, not Elixir terms; the DCO check and the governance files | [#1](https://github.com/ScriptKittyOS/beam_mcp/pull/1), [#2](https://github.com/ScriptKittyOS/beam_mcp/pull/2) |
| 001b | A request served by the protocol revision its `_meta` declares; released as 0.2.0 | [#7](https://github.com/ScriptKittyOS/beam_mcp/pull/7), [#8](https://github.com/ScriptKittyOS/beam_mcp/pull/8) |
| 002 | The stateless Streamable HTTP transport; released as 0.3.0 | [#9](https://github.com/ScriptKittyOS/beam_mcp/pull/9) |
| 003 | Release 0.3.1: four fixes to the HTTP transport | [#13](https://github.com/ScriptKittyOS/beam_mcp/pull/13) |
| 004 | The quality gate: one verdict per step, the licence population derived, a review bound to a tree | [#12](https://github.com/ScriptKittyOS/beam_mcp/pull/12) |
| 006 | The test harness reads a closed connection correctly | [#16](https://github.com/ScriptKittyOS/beam_mcp/pull/16) |
| 007 | `authorize_body/2`, a hook after the body is read, so body-signature authentication is possible | [#20](https://github.com/ScriptKittyOS/beam_mcp/pull/20) |

## 0.4.0 and 0.5.0: the catalog and the connectome

| slice | what it committed | pull request |
|---|---|---|
| 008 | One catalog contract carrying tools, resources and prompts | [#21](https://github.com/ScriptKittyOS/beam_mcp/pull/21) |
| 009 | The connectome vocabulary, and a gate step that keeps working records out of the public tree | [#22](https://github.com/ScriptKittyOS/beam_mcp/pull/22) |
| 010 | The connectome data model: nodes, edges, graphs, with a sign slot the package never fills | [#23](https://github.com/ScriptKittyOS/beam_mcp/pull/23) |
| 011 | The declared connectome, built from the catalog and the compiled code | [#24](https://github.com/ScriptKittyOS/beam_mcp/pull/24) |
| 012 | Canonical bytes, a hash, and DOT, GraphML and JSON exports | [#25](https://github.com/ScriptKittyOS/beam_mcp/pull/25) |
| 013 | The observed connectome: a dispatch span, a collector, a guarded tracer | [#26](https://github.com/ScriptKittyOS/beam_mcp/pull/26) |
| 014 | The diff engine: declared against observed, four classes and a coverage bound | [#27](https://github.com/ScriptKittyOS/beam_mcp/pull/27) |
| 015 | Release 0.4.0 | [#28](https://github.com/ScriptKittyOS/beam_mcp/pull/28) |
| 016 | Reachability queries: reachable, reachable without a gate, dominators | [#29](https://github.com/ScriptKittyOS/beam_mcp/pull/29) |
| 016a | The official MCP conformance suite, two rows, run in CI | [#30](https://github.com/ScriptKittyOS/beam_mcp/pull/30), [#31](https://github.com/ScriptKittyOS/beam_mcp/pull/31) |
| 016b | The resources primitive and one pagination codec | [#35](https://github.com/ScriptKittyOS/beam_mcp/pull/35) |
| 016c | The prompts primitive, on the tools' validation path | [#36](https://github.com/ScriptKittyOS/beam_mcp/pull/36) |
| 016d | The sign vocabulary | [#33](https://github.com/ScriptKittyOS/beam_mcp/pull/33) |
| 017 | The connectome on the wire: three read-only resources and a tool the host writes | [#37](https://github.com/ScriptKittyOS/beam_mcp/pull/37) |
| 018 | Release 0.5.0 | [#38](https://github.com/ScriptKittyOS/beam_mcp/pull/38), [#39](https://github.com/ScriptKittyOS/beam_mcp/pull/39) |
| 028b | The will-not-implement page, each entry held by a test | [#32](https://github.com/ScriptKittyOS/beam_mcp/pull/32) |
| 028c | The documentation ships in the Hex tarball | [#34](https://github.com/ScriptKittyOS/beam_mcp/pull/34) |

## 0.6.0 to 0.8.0: hardening, supply chain and the signer seam

| slice | what it committed | pull request |
|---|---|---|
| 021 | The canonical envelope names its algorithm; SHA-384 and SHA-512 by option | [#42](https://github.com/ScriptKittyOS/beam_mcp/pull/42) |
| 022 | The OTP floor (27) enforced at compile time | [#44](https://github.com/ScriptKittyOS/beam_mcp/pull/44) |
| 023 | CI on three OTP/Elixir pairs | [#45](https://github.com/ScriptKittyOS/beam_mcp/pull/45) |
| 024 | The dependency audit as a gate step | [#47](https://github.com/ScriptKittyOS/beam_mcp/pull/47) |
| 025 | Build provenance over the Hex tarball | [#48](https://github.com/ScriptKittyOS/beam_mcp/pull/48) |
| 026 | The security policy, shipped with the package | [#49](https://github.com/ScriptKittyOS/beam_mcp/pull/49), [#50](https://github.com/ScriptKittyOS/beam_mcp/pull/50) |
| 027a | Dialyzer in the gate and the review instruments | [#51](https://github.com/ScriptKittyOS/beam_mcp/pull/51) |
| 027b | The tracer in an OTP trace session of its own; opt-in git hooks | [#52](https://github.com/ScriptKittyOS/beam_mcp/pull/52) |
| 028 | API stability: the public surface pinned, the policy, the upgrade guide | [#53](https://github.com/ScriptKittyOS/beam_mcp/pull/53) |
| 029 | The threat model; JSON nesting bounded before decoding | [#40](https://github.com/ScriptKittyOS/beam_mcp/pull/40) |
| 029a | The HTTP body read deadline | [#41](https://github.com/ScriptKittyOS/beam_mcp/pull/41) |
| 029b | The HTTP/2 connection deadline | [#43](https://github.com/ScriptKittyOS/beam_mcp/pull/43) |
| 030 | Governance and succession; every workflow pinned by SHA | [#54](https://github.com/ScriptKittyOS/beam_mcp/pull/54) |
| 031 | The export-control statement; REUSE compliance | [#55](https://github.com/ScriptKittyOS/beam_mcp/pull/55) |
| 032 | Release 0.6.0 | [#56](https://github.com/ScriptKittyOS/beam_mcp/pull/56) |
| 033 | The signer seam: `BeamMCP.Signer`, `Signer.None`, `Canonical.signature/3`; released as 0.7.0 | [#57](https://github.com/ScriptKittyOS/beam_mcp/pull/57), [#58](https://github.com/ScriptKittyOS/beam_mcp/pull/58) |
| 035 | Release 0.8.0, the quiet minor | [#59](https://github.com/ScriptKittyOS/beam_mcp/pull/59) |

## 0.9.0 and 0.10.0

| slice | what it committed | pull request |
|---|---|---|
| 036 | The `:server` seam on both transports | [#64](https://github.com/ScriptKittyOS/beam_mcp/pull/64) |
| 037 | `scheme:` and `key_id:` beside the signature | [#64](https://github.com/ScriptKittyOS/beam_mcp/pull/64) |
| 038 | Release 0.9.0 | [#64](https://github.com/ScriptKittyOS/beam_mcp/pull/64) |
| 039 | The documentation free of em dashes | [#73](https://github.com/ScriptKittyOS/beam_mcp/pull/73) |
| 040 | The suite in FIPS mode in CI, on the validated OpenSSL FIPS provider | [#73](https://github.com/ScriptKittyOS/beam_mcp/pull/73) |
| 041 | A CycloneDX SBOM attested to every release | [#73](https://github.com/ScriptKittyOS/beam_mcp/pull/73) |
| 042 | README's schedule follows the road to 1.0.0 | [#73](https://github.com/ScriptKittyOS/beam_mcp/pull/73) |
| 043 | Release 0.10.0 | [#73](https://github.com/ScriptKittyOS/beam_mcp/pull/73) |

Work that was not a numbered slice (the OpenSSF Best Practices pages, continuity, dependency
updates) is in the pull requests and the CHANGELOG. A slice that lands later is added here in
the pull request that lands it.
