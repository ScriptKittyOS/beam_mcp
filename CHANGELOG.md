<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.2] — unreleased

### Changed — two fields are REMOVED from results for legacy-declared requests

**Read this before upgrading if any client sends `_meta` naming `2025-11-25`.** A result
answering such a request no longer carries `resultType` or `_meta`
`io.modelcontextprotocol/serverInfo`. In `0.1.0` it carried both. This is not limited to
`ping` — it applies to every method reaching that path, `tools/list`, `tools/call` and
`shutdown` included:

    0.1.0:  tools/list + _meta 2025-11-25
      -> {"result":{"_meta":{"io.modelcontextprotocol/serverInfo":{...}},"resultType":"complete","tools":[...]}}
    0.1.2:  tools/list + _meta 2025-11-25
      -> {"result":{"tools":[...]}}

A client that reads `result.resultType` on that path gets `nil` after what is numbered a patch
release. It is numbered a patch because `0.y.z` is outside semver's compatibility contract and
because the removed fields were never correct — they announced a revision the client did not
ask for. **Neither of those makes the wire change smaller**, and the honest signal for a
published package where the JSON *is* the API would arguably be `0.2.0`. Recorded here as the
removal it is so the number is not the only thing a reader has to go on. Raised by review;
the version choice is the owner's at publish time.

Requests declaring `2026-07-28`, and requests with no `_meta` at all, are unaffected.

### Fixed

- **A request declaring `2025-11-25` through per-request `_meta` is now served as
  `2025-11-25`.** The `_meta` clause branched on the method and never on the declared
  revision, so `ping` was refused with `-32601` at every revision reaching it, and every
  result was decorated with `resultType` and `_meta` `serverInfo` — two fields `2026-07-28`
  introduced and `2025-11-25` does not define. Both halves came from one version-blind `cond`.

  Measured against `0.1.1`, each message the first and only one on a fresh state. (`0.1.1`
  here and `0.1.0` above name the **same** before-state: `0.1.1` changed documentation only,
  so the version-blind clause is byte-identical at the `v0.1.0` tag and on `main`. Two numbers
  for one behaviour, flagged by review as a readability trap.)

      ping + _meta 2025-11-25   ->  {"error":{"code":-32601,"message":"Method not found: ping"},...}
      tools/list + _meta 2025-11-25
        ->  {"result":{"_meta":{"io.modelcontextprotocol/serverInfo":{...}},"resultType":"complete",...}}

  and after:

      ping + _meta 2025-11-25   ->  {"id":1,"jsonrpc":"2.0","result":{}}
      tools/list + _meta 2025-11-25  ->  {"result":{"tools":[...]}}          # no resultType, no _meta

  Live in published `0.1.0`. The refusal is reachable only through `_meta`: a bare `ping`, and
  a `_meta` carrying no `io.modelcontextprotocol/protocolVersion`, were always answered.

  Why a `_meta` may name the legacy revision at all: this server advertises `2025-11-25` in
  `server/discover` and lists it in the `-32022` `supported` payload, and the specification
  tells a client receiving `-32022` to select from `supported` and **retry the request** —
  which produces exactly this message. `_meta` fixes statelessness; the revision it names
  fixes the semantics.

### Note on `0.1.1`

`0.1.1` reached `main` and was **never published to Hex**. `mix.exs` now reads `0.1.2`, so
`0.1.1` will not exist as a release and the moduledoc fix recorded below ships inside `0.1.2`.
The `0.1.1` section is left exactly as written; this note is appended rather than a rewrite.

## [0.1.1] — unreleased

### Fixed

- **`BeamMCP.Server` is documented.** It carried `@moduledoc false`, so hexdocs rendered the
  package's principal module as hidden and the two warnings below were emitted on every build.

### Was known, now fixed

**Two hexdocs warnings**, reproduced by running `mix docs` rather than taken from the publish
output:

    warning: documentation references module "BeamMCP.Server" but it is hidden
    warning: documentation references module "BeamMCP.Server" but it is hidden

`BeamMCP.Server` carries `@moduledoc false` — inherited verbatim from the tree it was extracted
from, where it was an internal module and the annotation was correct. It is now the package's
principal public module, and `BeamMCP.ToolCatalog`'s docs link to it, so the published docs
reference a module hexdocs will not render. The annotation stopped being true the moment the
code left the umbrella, and nothing caught it because a hidden module is not a compile warning
and the gate does not run `mix docs`.

## [0.1.0] — 2026-09-06

First release. Tag `v0.1.0`, an annotated tag whose object is `69c8159` and whose commit is
`2add129e65d04759ce67c77520208b854c05dcee`.

**Package digest, read from the Hex API rather than from a terminal:**

    $ curl -s https://hex.pm/api/packages/beam_mcp/releases/0.1.0 | jq '{checksum, inserted_at, has_docs}'
      checksum:     b8c351933260d90844eae1614ae4759cf979d4a524ee139fbbef1c2dfaab5e7f
      inserted_at:  2026-09-06T20:57:51.749883Z
      has_docs:     true
      requirements: ["jason"]

The registry's own value is the one recorded, because a checksum printed by the machine that
built the tarball attests to that machine and not to what a consumer will fetch.

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

### Fixed

- **Error payloads no longer carry `inspect/1` output.** A failed call returned Elixir term
  syntax — a map literal and a bare atom — to a client with no way to parse it and no reason
  to know the server's language. `structuredContent` now carries the error as a JSON object
  and `content` carries a sentence.

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
- Streamable HTTP and the rest of the non-stdio surface (see below).
- Streamable HTTP, `subscriptions/listen`, MRTR, tasks, authorization, elicitation, sampling
  and roots are not implemented. This is a stdio, tools-only server.
