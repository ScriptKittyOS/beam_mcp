<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] — unreleased

### Added — stateless Streamable HTTP transport

`BeamMCP.Transport.HTTP` is a `Plug` serving `2026-07-28` at one endpoint. Every request stands
alone: **no sessions, no `Mcp-Session-Id`, no SSE resumability**, all three removed from the
transport in that revision. `handle_message/2` gains no clause — HTTP is a second caller of the
existing core.

`plug` and `bandit` are **optional** dependencies, so a host using only stdio does not pull an
HTTP server into its tree.

**Two options have no defaults, and a host that omits either cannot start.**

    Bandit.child_spec(
      plug: {BeamMCP.Transport.HTTP,
             tool_catalog: MyApp.Catalog,
             dispatch: &MyApp.Dispatch.call/3,
             authorize: &MyApp.Auth.check/1,                  # required, no default
             allowed_origins: ["https://app.example.com"]},   # required, no default
      port: 4000, ip: {127, 0, 0, 1})

This package cannot decide who may call your tools — it has no view of your identity model, and
deciding for you would be claiming something it cannot keep. But a Plug that serves `tools/call`
to anyone who can reach the port is a confused-deputy surface, and "the host should have
authenticated" is documentation rather than a control. **A required argument with no default is
a contract**, because you cannot start without answering it. To accept every caller, say so
explicitly: `authorize: fn _conn -> :ok end`.

`allowed_origins` exists because the specification makes validating `Origin` a MUST, to prevent
DNS rebinding. `:any` is available and must be chosen deliberately.

**What the transport enforces**, each a MUST of the transport specification:

| requirement | behaviour |
|---|---|
| `MCP-Protocol-Version` on every POST | missing -> `400`, `-32020` |
| header must match the body's `_meta` | mismatch -> `400`, `-32020` |
| `Mcp-Method` on every request (**not** on notifications, which the revision leaves undefined) | missing or mismatched -> `400`, `-32020` |
| `Mcp-Name` on `tools/call` | missing or mismatched -> `400`, `-32020` |
| `Mcp-Param-{Name}` for every parameter the tool's schema marks `x-mcp-header` | mismatched, or omitted while the body carries the value -> `400`, `-32020` |
| an encoded header value is decoded before comparison | `=?base64?…?=`, on `Mcp-Name` and `Mcp-Param-{Name}` **only** — the two headers the specification scopes it to |
| `initialize`, `notifications/initialized`, `ping` | `404`, `-32601` — deleted by this revision |
| unsupported version | `400`, `-32022` |
| invalid `Origin` | `403` |
| unknown **method** | `404`, `-32601` |
| unknown **tool** | `200` with `-32601` in the body — a live endpoint, a bad argument |
| non-POST (a SHOULD, not a MUST) | `405` with `Allow: POST` |

The mirrored-parameter population is derived from **the tool's `inputSchema`**, not from the
headers the caller sent. The specification's fourth server-behaviour row is *"client omits header
but value is in body → server MUST reject"*, which is unenforceable if the caller's own headers
define what gets checked; and `x-mcp-header` carries a header **name portion** pointing at a
property path that may be nested, so the mapping cannot be recovered by lowercasing a header
suffix into a top-level argument key.

**Every header is validated in all of its values, not the first.** A duplicated header — a
satisfying value followed by a hostile one — is the same smuggling the MUST above exists to
stop, and the first version of this transport read only the first value of four of them. There
is now one read path, `header_values/2`, and one mutant per header proving each is pinned
(`logs/mutation.md`).

`Mcp-Method` and `Mcp-Name` are validated against the body because the specification says why:
*"a load balancer routing on the header value while the MCP server executes based on the body
value."* An earlier draft of this table omitted both while calling itself a list of MUSTs, and a
reviewer demonstrated the consequence — `Mcp-Method: tools/list` with a `tools/call` body
returned `200` and reached dispatch.

**What this closes.** On stdio a `tools/call` with no handshake and no `_meta` is served —
defensible there, because whoever can write to that transport already has the host's privileges.
Over HTTP that argument does not hold, and the specification removes the case: the version header
is mandatory, so a request with no era established is *malformed* and refused as a protocol
matter rather than a policy choice.

### Added — `ttlMs` and `cacheScope` on `tools/list`

`2026-07-28` requires both via `CacheableResult`. No release before this one emitted them.

Neither is the package's to invent: `ttlMs` is a freshness hint about a catalog the host owns,
and `cacheScope` is a disclosure decision — `"public"` lets shared intermediaries cache a tool
list, and a tool list can be sensitive. Both are host-supplied through `tools_ttl_ms:` and
`tools_cache_scope:`, and **the default is the non-permissive one** (`0` and `"private"`). A
package that picked the permissive default on a host's behalf would be making a disclosure
decision it cannot keep.

### Known limitation — `authorize/1` cannot see the request body

It runs **before** the body is read and returns `:ok | {:error, reason}`, with no way to hand back
the `conn` it read from, so **body-signature authentication — an HMAC over the payload — is not
possible in it**. This does not fail as an error: a small request appears to work because the body
is already in the adapter's buffer, and a larger one hangs until the server's read timeout and
returns `408` with the connection dead (measured: 119 bytes `200`; 16 KiB and 200 KiB both `408`
at 15.0 s). A host that meets this by experiment would reasonably read it as a bug, so it is
written down.

Today: authenticate in a plug in front of this one that reads the body and re-supplies it, or
decide in `dispatch/3`, which is handed the decoded arguments. **This is an open design question,
not a final shape.** The likely answer is two hooks — `authorize/1` staying as the cheap pre-read
gate on headers, origin and peer, plus an optional post-read hook for body signatures — and that
belongs in its own release rather than in one that is otherwise finished. Designing an
authentication contract under release pressure is how the wrong one ships permanently.

### Changed — the recommended dependency requirement

`README.md` now recommends `{:beam_mcp, "~> 0.3.0"}`. `~> 0.3` admits `0.4.0`, and this package
documents wire breaks at the **minor** position while it is `0.x`.

### Changed — a host's exception no longer chooses the HTTP status

**Read this if a host tool, `authorize/1` or `tool_catalog` raises an exception carrying a
`:plug_status`** — `Plug.BadRequestError`, or Ecto's `NoResultsError` at 404, for instance. In
`0.2.0` there was no HTTP transport, so this is new behaviour rather than changed behaviour, but
it changed twice during this release and the second shape is what ships:

    a host tool raising Plug.BadRequestError
      -> HTTP 400, empty body, no JSON-RPC error object
    now
      -> HTTP 500, {"jsonrpc":"2.0","id":<the request id>,"error":{"code":-32603,...}}

An exception carrying a status means the **server** is signalling — Bandit raises
`Bandit.HTTPError` for a malformed transfer coding and its pipeline turns that into the response.
An exception out of **host** code carries no such authority however it is annotated, and letting
it through dropped the envelope on a path the protocol requires one, with no `id` to correlate
and no body to parse.

The rule is applied at every point host code runs in the request path — `authorize/1`,
`BeamMCP.ToolCatalog.fetch/2` and `BeamMCP.Server.handle_message/2` — and that population is
derived by grep rather than listed, because listing it is how the first cut of this fix covered
one of the three and shipped a comment claiming all of them.

### Added — `BeamMCP.ToolCatalog.fetch/2` is public API

One lookup answers "which tool does this name mean" for both the core and the HTTP transport's
header validation. Two lookups would be two answers, which is the disagreement the mirrored-header
mechanism exists to prevent. Its `@spec` says `{:ok, t} | :error` and three host-authored catalog
shapes raise instead; that is filed, not fixed here.

### Fixed — two failure modes found by measuring rather than by reasoning

- **A failure in the host's dispatch answered with an empty `500`.** It now answers
  `-32603 Internal error` **carrying no detail**; the reason still reaches the logger, where the
  host can see it. Leaking it to an HTTP caller would hand a possibly-unauthenticated party the
  host's internals.

  The first fix used `rescue`, which catches raises only. A reviewer showed `throw` and `exit`
  still producing the bare empty `500` this entry claimed had been eliminated — and `exit` is
  the shape that matters most, because **a `GenServer.call` timeout exits**, which is what a
  host calling a backend hits first. Now `catch`, covering all three.

- **`BeamMCP.Transport.Stdio` was documented.** It carried `@moduledoc false` — inherited from
  the tree it was extracted from, where it was internal — while `README.md` documents `run/1` as
  the entry point. Left alone, `0.3.0` would have published hexdocs in which the stdio transport
  is absent and the new HTTP transport beside it renders, which reads as deliberate.

  **This is the second instance of one defect: `BeamMCP.Server` shipped hidden in `0.1.0`.** The
  entry recording that one also recorded why nothing caught it — "a hidden module is not a
  compile warning and the gate does not run `mix docs`" — and the gate still did not, for two
  more releases. So `tools/gate.sh` now has a `docs` step, and it reads `mix docs`'s **output**
  rather than its exit code, because `mix docs` exits `0` on a warning:

      docs    FAIL (exit 0, 2 warnings)

  That line is from the probe in `slices/002-streamable-http/logs/probe-docs-gate.txt`, which
  reverts the moduledoc, shows the gate red, and restores it. Fixing an instance twice and the
  mechanism never is what the step is for.

- **The `403` for a refused caller carried the host's refusal reason.** `authorize/1` returns
  `{:error, term}`, and that term was `inspect`ed into the response body — on the one branch
  that is by definition unauthenticated. A reviewer recovered a planted bearer token and a
  database URL from it. The reason now goes to the log; the caller is told only `Forbidden`.

- **A non-map `_meta` crashed outside the rescue**, giving the same bare empty `500`. `_meta` is
  any JSON value once the body is an object, and reaching into a string raised in `Access.get/3`
  before the handler was entered. Now a `400`.

- **Five error paths poisoned the next request on a keep-alive connection**, and the first
  diagnosis of this was wrong in a way worth recording. It was reported here as a `413`
  problem. A reviewer could not reproduce it on `413` — and was right, because `413` already
  carried the updated connection out. The real defect was one level up: `with/else` clauses
  cannot see bindings made inside the `with`, so **every refusal after the body was read
  answered on the pre-read connection**. Bandit then framed the next request's bytes as this
  one's unread body, and the following request hung.

  Affected: missing protocol header, header mismatch, unsupported version, invalid JSON and
  non-object JSON. It is **size-dependent** — a few dozen bytes arrive in a single adapter read
  and look correct — which is why every test and every row of the first resilience table passed
  while five paths were broken. Found with a 16 KB body and two requests on one socket.

  Now every step returns the connection it was handed and every refusal answers on that one.
  Verified over a raw socket at 16 KB: all five paths answer, and the following request on the
  same connection returns `200`.

Request bodies are capped at 1 MiB. Without a cap, a body is an unbounded allocation an
unauthenticated caller controls.

## [0.2.0] — 2026-09-07

### Changed — two fields are REMOVED from results for legacy-declared requests

**Read this before upgrading if any client sends `_meta` naming `2025-11-25`.** A result
answering such a request no longer carries `resultType` or `_meta`
`io.modelcontextprotocol/serverInfo`. In `0.1.0` it carried both. This is not limited to
`ping` — it applies to every method reaching that path, `tools/list`, `tools/call` and
`shutdown` included:

    0.1.0:  tools/list + _meta 2025-11-25
      -> {"result":{"_meta":{"io.modelcontextprotocol/serverInfo":{...}},"resultType":"complete","tools":[...]}}
    0.2.0:  tools/list + _meta 2025-11-25
      -> {"result":{"tools":[...]}}

A client that reads `result.resultType` on that path gets `nil`. **That is why this is `0.2.0`
and not a patch.**

The argument for a patch was available and is rejected: `0.y.z` sits outside semver's
compatibility contract, and the removed fields were never correct — they announced a revision
the client did not ask for. Neither of those makes the wire change smaller. For a published
package the JSON *is* the API. For a client declaring `2025-11-25`: **a method that was
refused now answers** (`ping`), and **results on that path have lost two fields**. A `0.1.0`
consumer could have depended on either.

The field removal is the breaking-shaped half and is the whole case for the bump; the `ping`
change is additive and is not an argument for it.

**This paragraph had the direction backwards and it is worth saying where that came from.** It
read "a method that answered now refuses", which is true of no method in this release. That
sentence was one of the two grounds given for choosing `0.2.0`, and it travelled from the
decision through to this file without anyone checking it — the second ground, the field removal,
is correct and carries the decision on its own. A reviewer caught it by enumerating every method
for a client declaring `2025-11-25` on both this tree and `0.1.0`'s, rather than by reading any
of the places it was written down:

    ping         0.1.0: REFUSED -32601      0.2.0: answered
    every other method: unchanged status on both

Recorded rather than quietly reworded, because a false statement about wire behaviour in a
published package's changelog is the paragraph a consumer reads to decide whether to upgrade,
and because the correction strengthens the case for `0.2.0` rather than weakening it. The minor bump is the honest signal, and the
`### Changed` heading above stays exactly as it was written when the number still disagreed
with it.

Owner decision, 2026-09-07.

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

### Note on `0.1.1` — why the published versions jump `0.1.0` -> `0.2.0`

**`0.1.1` does not exist as a release and never will.** It reached `main`, was never published
to Hex, and `mix.exs` now reads `0.2.0`. Its one change — a moduledoc for `BeamMCP.Server`,
which shipped hidden in `0.1.0` — **ships inside this release**, and its entry is kept below
under its original heading rather than being folded up or deleted.

So a reader comparing Hex to this file sees `0.1.0` then `0.2.0`, with a `0.1.1` section in
between that names no release. That is the whole explanation, stated here rather than left as a
gap to be reconstructed: the number was taken on `main`, the release it was taken for never
happened, and the work it covered is in `0.2.0`.

The `0.1.1` section below is left exactly as written. This note is appended rather than a
rewrite, per the corrections-are-appended rule.

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
