<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Nothing is published yet. The sections below describe what a first release would contain.

### Why 0.1.0 was not published at `c5da02f`

The extraction was complete and the gate was green, and the package was still not fit to
publish. A revision check found the reason:

> **a `2026-07-28` request answered with a `2024-11-05`-shaped result that looks like success.**

A client speaking the current revision sent `tools/list` carrying its version and capabilities
in `_meta`, exactly as that revision requires, and got back a well-formed result — with no
`resultType`, no `_meta` `serverInfo`, and none of the fields the revision mandates. Not an
error a client could act on. A wrong answer wearing the shape of a right one.

The specification names this case itself: a modern client against a legacy server may be
rejected, met with silence, *"or even process an era-ambiguous method under legacy semantics."*
Publishing that under a name as general as `beam_mcp` would have put a library on Hex that
fails quietly against the revision most evaluators would try first.

### Added

- The MCP protocol core as a standalone package: `BeamMCP.Server`,
  `BeamMCP.Transport.Stdio`, `BeamMCP.Schema`, `BeamMCP.ToolSpec` (`083838e`).
- `BeamMCP.ToolCatalog`, a behaviour, and a published dispatch callback type. Injection
  without a specification is a claim with nothing behind it (`083838e`).
- `:input_schema` on `ToolSpec`. The catalog supplies a tool's schema, `tools/list` advertises
  it and `tools/call` enforces the same one (`c5da02f`).
- **Dual-era protocol support: `2026-07-28` and `2025-11-25`.** `server/discover`, per-request
  `_meta` version handling, `resultType` and `_meta` `serverInfo` on modern results, and
  `UnsupportedProtocolVersionError` (`-32022`) listing the supported set.
- A quality gate (`tools/gate.sh`) and CI, with no ratchet baseline (`ee63228`).
- Transport tests, with coverage demonstrated by mutation (`13a6238`).
- `README.md`, `CONVENTIONS.md`.

### Changed

- The tool-name check routes through the injected catalog. Previously `tools/list` honoured
  the injected catalog while `tools/call` consulted a hardcoded one, so a tool could be
  advertised and then refused (`083838e`).
- `:dispatch` and `:tool_catalog` are injected; `:tool_catalog` is required (`083838e`).
- The advertised server name is a `:server_name` option defaulting to `beam_mcp` (`083838e`),
  and the advertised version is read from the project config rather than restated in the
  source (`1ac057e`).
- Argument keys are derived from the tool's schema; values pass through unchanged, since
  coercing a string to a domain term belongs to the host (`c5da02f`).

### Removed

- Per-tool `input_schema/1` clauses, `input_schema_for/1`, the hardcoded argument-key
  allowlist and the domain value coercion — one consumer's domain data in a generic module
  (`c5da02f`).
- **`2024-11-05` is no longer supported.** A client requesting it receives `-32022`.
- JSON-RPC batching is refused. It was added in `2025-03-26` and removed in `2025-06-18`, so
  it is required by exactly one revision of five and by neither of the two supported here.
- `ping` at the modern era. It was removed in `2026-07-28`; the legacy era still answers it.

### Not adopted, deliberately

Three optional items from `2025-11-25`, recorded so their absence is not read as an oversight:

- **JSON Schema 2020-12 dialect declaration.** `BeamMCP.Schema` is a deliberately small
  subset — `type`, `properties`, `required`, `additionalProperties`, bounds. Declaring a
  dialect it does not fully implement would claim more than it does.
- **`title` on tools.** Optional human-readable display name. Nothing in the package needs it,
  and a catalog that wants one can carry it when the field is supported end to end.
- **`icons` on tools.** Optional metadata, no consumer.

Each is additive and can be adopted without a breaking change.

### Known gaps

- CI has not run against this history at the time of writing; a committed workflow is not a
  working one until a run exists.
- Error payloads carry `inspect/1` output, so Elixir term syntax reaches the wire. A boundary
  defect at every revision, and its own slice before publish.
- Streamable HTTP, `subscriptions/listen`, MRTR, tasks, authorization, elicitation, sampling
  and roots are not implemented. This is a stdio, tools-only server.
