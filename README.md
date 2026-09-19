<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# BeamMCP

A Model Context Protocol server core for the BEAM. Protocol handling, two transports — stdio and
a stateless Streamable HTTP `Plug` — and JSON Schema validation, with the tool catalog and the
dispatch function injected by the host.

The package holds no tools, no domain, and no policy. It decides what a well-formed request is
and refuses one that is not; what a tool *does* is the host's business.

```elixir
def deps do
  [{:beam_mcp, "~> 0.6.0"}]
end
```

**`~> 0.6.0`, not the more usual `~> 0.6`.** While this package is `0.x` it documents breaks
at the **minor** position, and it has used that position five times: `0.2.0` removed two
fields from results for legacy-declared requests, `0.3.0` added the HTTP transport and the
`ttlMs`/`cacheScope` fields `2026-07-28` requires on `tools/list`, `0.4.0` replaced the
catalog behaviour a host implements — `BeamMCP.ToolCatalog` by `BeamMCP.Catalog` — a break in
the host contract rather than on the wire, and `0.5.0` reads a request's `_meta` at
`params._meta` and refuses it at the top level (on the wire), renames the one sign the package
writes and moves `schema_version` to `2` (in the exported bytes), and requires a catalog's
`resources` and `prompts` lists to hold the package's structs (the host contract), and `0.6.0`
names the canonical envelope's algorithm in its bytes and moves `schema_version` to `3` (in the
exported bytes), each with a how-to-tell sentence in the changelog. `~> 0.6` admits `0.7.0`, so
it would carry you across the next such break on a routine `mix deps.update`; `~> 0.6.0` does
not. The tighter form is deliberate and is not an over-pin to be tidied away. What the pin
buys is written down: [`docs/api-stability.md`](docs/api-stability.md) says what is public
(what ex_doc lists, `docs/public-api.txt` line by line), how a deprecation runs (three steps,
three minors), and what a `0.x` break must say; a census holds the surface to that record.
[`UPGRADING.md`](UPGRADING.md) lists every break so far, one line each, and what `1.0` will ask.

**From `0.6.0`, the tarball is attested, and the attestation binds to the checksum hex.pm
shows.** On a release tag, CI builds the tarball with `tools/release_tarball.sh` — the
one way that gives the same bytes on every machine (`mix hex.build` on a working tree carries
that machine's file modes and directory order) — attests its SHA-256 with GitHub's
build-provenance attestation, and verifies the attestation against the bytes hex.pm serves. A
release verifies when it was published with the same script; `gh attestation verify
beam_mcp-<version>.tar --repo ScriptKittyOS/beam_mcp` checks it. `0.5.0` and earlier carry no
attestation ([`docs/provenance.md`](docs/provenance.md)).

## Two contracts

Injection without a specification is a claim with nothing behind it, so both are declared.

**`BeamMCP.Catalog`** — the host names what it offers.

`capabilities/0` returns a map with three required keys. `tools` holds `BeamMCP.ToolSpec`
structs; `resources` holds `BeamMCP.ResourceSpec` and `BeamMCP.ResourceTemplateSpec` structs
— one list, two kinds, no `uri` or `uri_template` twice — and a catalog that lists either
also exports `read_resource/1`;
`prompts` holds `BeamMCP.PromptSpec` structs, each with its `BeamMCP.PromptArgument` list,
and a catalog that lists a prompt exports `get_prompt/2`.
**An absent key is a malformed catalog, not an empty one**, and `BeamMCP.Server.new/1`
refuses it at startup rather than at the first request — as it refuses a `resources` or
`prompts` entry that is not its struct, a repeated key, and a listed resource, template or
prompt with no reader.

```elixir
defmodule MyApp.Catalog do
  @behaviour BeamMCP.Catalog

  @impl true
  def capabilities do
    %{
      resources: [
        %BeamMCP.ResourceSpec{uri: "weather://places", name: "places", mime_type: "text/plain"},
        %BeamMCP.ResourceTemplateSpec{uri_template: "weather://place/{name}", name: "place"}
      ],
      prompts: [
        %BeamMCP.PromptSpec{
          name: "forecast",
          description: "Ask for a forecast.",
          arguments: [%BeamMCP.PromptArgument{name: "place", required: true}]
        }
      ],
      tools: [
      %BeamMCP.ToolSpec{
        name: :get_weather,
        command_class: :observe,
        mode: :read_only,
        description: "Read the current weather for a place.",
        input_schema: %{
          "type" => "object",
          "properties" => %{"place" => %{"type" => "string"}},
          "required" => ["place"],
          "additionalProperties" => false
        }
      }
        ]
    }
  end

  @impl true
  def read_resource("weather://places"), do: {:ok, [%{uri: "weather://places", text: "Oslo\nLima"}]}
  def read_resource("weather://place/" <> name), do: {:ok, [%{uri: "weather://place/#{name}", text: "12°C"}]}

  @impl true
  def get_prompt("forecast", %{place: place}),
    do: {:ok, %{messages: [%{role: :user, text: "What is the forecast for #{place}?"}]}}
end
```

**Resources are advertised and read from one reader.** `resources/list` and
`resources/templates/list` serve what `capabilities/0` names, sorted by `uri` and
`uriTemplate`; `resources/read` accepts a uri only when that same list names it or a listed
template matches it (RFC 6570 `{var}` for one non-empty segment, `{+var}` across segments —
nothing more is claimed, and a template with any other expression, or a bare brace, is
refused at startup) and refuses any other as not found before the reader runs — `-32602`
with the uri as data under `2026-07-28`, `-32002` under `2025-11-25`, the code each revision
names for it — so what is advertised and what is readable cannot drift. The read is the
catalog's `read_resource/1`: `{:ok, contents}` with `text` as a string or `blob` as raw bytes
(base64 on the wire), or `{:error, reason}`, carried to the client as the same not-found code
with the reason as data. Both lists are
paginated by one opaque cursor (`BeamMCP.Cursor`, keyed on the item rather than an offset, so
a list that changes between pages never skips an item that was there before); the page size
is `BeamMCP.Server.new/1`'s `page_size:` (default 50), and a cursor from another list is
refused by name. `ttlMs` and `cacheScope` on the three results are `resources_ttl_ms:` and
`resources_cache_scope:`, defaulting to `0` and `"private"` for the reasons the tools pair
does. The server sends no notifications: `resources` is advertised with `listChanged: false`
and `subscribe: false`.

**Prompts take the tools' own validation path.** `prompts/list` serves what `capabilities/0`
names, sorted by name and paginated by the same cursor; `prompts/get` renders only a prompt
the list names — an unknown name is `-32602` with the name as data, before the reader runs —
and its arguments are validated by the tools validator over a JSON Schema derived from the
declared argument list (`BeamMCP.PromptSpec.argument_schema/1`: one `string` property per
argument, `required` from the flags, nothing undeclared admitted), then handed to
`get_prompt/2` keyed by the declared names, as a tool's arguments reach its dispatch. One
validator, one normaliser, two callers; a caller's argument name becomes an atom on neither
path, measured over 10,000 distinct keys. The reader answers `{:ok, %{messages: [%{role:
:user | :assistant, text: ...}], description: ...}}` — text content only, as for tools — or
`{:error, reason}`, carried as `-32602` with the reason as data. `prompts/list` carries
`prompts_ttl_ms:` / `prompts_cache_scope:` (defaults `0` / `"private"`); `prompts/get` is
not cacheable and carries neither. `prompts` is advertised with `listChanged: false`;
`completion/complete` belongs to the separate `completions` capability, which this package
does not advertise.

**The dispatch callback** — the host does the work.

```elixir
@type dispatch :: (atom(), map(), keyword() -> {:ok, term()} | {:error, term()})
```

## Running it

```elixir
BeamMCP.Transport.Stdio.run(
  catalog: MyApp.Catalog,
  dispatch: &MyApp.Dispatch.call/3,
  server_name: "my-app"
)
```

`:catalog` is required. `:dispatch` is required for `tools/call`. `:server_name` defaults
to `beam_mcp`, and a host that wants its own name in `initialize` says so.

### The OTP floor

This package requires **Erlang/OTP 27 or newer** and **Elixir 1.17 or newer** — 1.17 is the
oldest Elixir that supports OTP 27, so the two minimums are one coherent pair — the OTP half
enforced at compile time:
`mix.exs` reads `:erlang.system_info(:otp_release)` at `project/0` and a below-floor build fails
with a message that names the floor and why, rather than compiling and failing later in a way
that looks like a defect here. The reason, so the floor is not raised by the next person who
finds it inconvenient: OTP **27.0** added the `trace` module — isolated trace sessions,
`:trace.session_create/3` — and the connectome tracer runs inside one of its own, so that a
process a host already traces is traced too and a host's own patterns and flags are never
touched (`docs/connectome-observed.md`); so 27 is the hard requirement. It is also the oldest
release this project *supports*: the lowest leg the CI matrix runs the suite
on, so that support is a measurement and not a hope. The suite runs on OTP 27, 28 and 29 in CI
(the floor, the pinned line and the newest pair the compatibility table lists — `mix format` is
measured on the pinned line only, the formatter being one program) and on 28 on the
maintainers' machines; releases older than 27 are neither tested nor supported.

## One schema, one source

A tool's schema lives on its `BeamMCP.ToolSpec`. `tools/list` advertises **that** schema and
`tools/call` enforces **that** schema, so the contract a client is shown and the contract it is
held to cannot drift apart. Argument keys are derived from the schema's `properties` and reach
`dispatch` as **atoms** — a tool declaring `"place"` is dispatched `%{place: "Oslo"}`, not
`%{"place" => "Oslo"}`. Values are passed through unchanged, because turning a string into a
domain term is the host's job and a generic layer that guesses has acquired someone else's
domain.

A `BeamMCP.ToolSpec` that omits `input_schema` is a tool with no arguments: it advertises an open
empty object, so `tools/call` refuses nothing and dispatch is handed `%{}` whatever the client
sent.

Validation is a deliberately small subset of JSON Schema — `type`, `properties`, `required`,
`additionalProperties`, and bounds. It refuses rather than guesses, and it is not a general
validator.

## Transports

**stdio** — `BeamMCP.Transport.Stdio.run/1`, newline-delimited JSON-RPC over a pipe.

**HTTP** — `BeamMCP.Transport.HTTP`, a `Plug` serving the `2026-07-28` stateless model at one
endpoint: no sessions, no `Mcp-Session-Id`, no SSE resumability. `plug` and `bandit` are optional
dependencies; a stdio-only host does not pull them in.

**If you add `plug` to a host that already has this package compiled, run
`mix deps.compile beam_mcp --force`.** The module is guarded by `Code.ensure_loaded?(Plug)`,
which is evaluated once at compile time and is not a tracked compile-time dependency, so adding
the dependency afterwards does not rebuild this package: `mix compile` reports success and
`BeamMCP.Transport.HTTP` does not exist. Changing this package's version rebuilds it and needs
no such step.

```elixir
Bandit.child_spec(
  plug: {BeamMCP.Transport.HTTP,
         catalog: MyApp.Catalog,
         dispatch: &MyApp.Dispatch.call/3,
         authorize: &MyApp.Auth.check/1,
         allowed_origins: ["https://app.example.com"]},
  port: 4000,
  ip: {127, 0, 0, 1}
)
```

Or mounted inside an existing router, where `forward` matches on a path prefix and the Plug
serves everything under it:

```elixir
defmodule MyApp.Router do
  use Plug.Router
  plug :match
  plug :dispatch

  forward "/mcp",
    to: BeamMCP.Transport.HTTP,
    init_opts: [
      catalog: MyApp.Catalog,
      dispatch: &MyApp.Dispatch.call/3,
      authorize: &MyApp.Auth.check/1,
      allowed_origins: ["https://app.example.com"]
    ]

  match _, do: send_resp(conn, 404, "")
end
```

**`authorize` and `allowed_origins` are required and have no defaults.** Omit either and the Plug
raises when it is initialised — at start, not on the first request.

That is deliberate. This package cannot decide who may call your tools: it has no view of your
identity model, and deciding for you would be claiming something it cannot keep. But serving
`tools/call` to anyone who can reach the port is a confused-deputy surface, and a README sentence
telling you to authenticate is documentation rather than a control. **A required argument with no
default is a contract, because you cannot start without answering it.** To accept every caller,
say so: `authorize: fn _conn -> :ok end`.

**`authorize/1` must not read the request body.** It runs before this Plug reads it, and
`Plug.Conn.read_body/2` can be called once: a host that consumes the body in `authorize/1`
leaves the transport nothing to parse, and the request fails as a parse error rather than as
whatever the host meant. Authorize on the `Plug.Conn` — headers, peer, assigns set by an earlier
plug — and if a decision genuinely needs the payload, make it in `dispatch/3`, which is handed
the decoded arguments.

Said plainly, because it is a real limitation and not a preference: **body-signature
authentication is not possible in `authorize/1`.** The callback runs before the body is read and
returns `:ok | {:error, reason}`, with no way to hand back the `conn` it read from. A host that
reads the body there does not get an error — a small request appears to work because the body is
already in the adapter's buffer, and a larger one hangs until `read_timeout:` lapses and then
returns `408` with the connection dead. Measured: 119 bytes `200`, 16 KiB and 200 KiB both `408`
after 15.0 s. Today the workarounds are a plug in front of this one that reads the body and re-supplies it,
or deciding in `dispatch/3`.

### `authorize_body/2`, the optional post-read hook

That design question is settled, and not by changing `authorize/1`. **`authorize/1` keeps its
position before the body read**, because that is what refuses an unauthenticated caller without
buffering megabytes on their behalf. A second, **optional** hook sits beside it:

```elixir
authorize_body: fn conn, body -> MyApp.Auth.verify_signature(conn, body) end
```

**`:authorize_body` is called after the body is read and before it is decoded, and the second
argument is the request body exactly as received.** Not a re-encoding of it: a signature covers
bytes, so a hook handed `Jason.encode!(Jason.decode!(body))` would reject every correct signature
while looking like a fault in the host's cryptography.

It is optional — absent, it is skipped and nothing changes. Present, it must be a 2-arity
function or the Plug raises at `init/1`, so a wrong arity is a startup failure rather than a
per-request one.

A refusal is opaque: **the reason goes to the log, never to the caller**, exactly as with
`authorize/1`, so a client cannot tell "no signature" from "bad signature". A refusal here
answers `403`; a hook that raises answers `500` and tells the caller nothing.

**A post-read refusal does not close the connection.** The pre-read refusals do, because the body
is still on the wire and the adapter would drain it; by the time this hook runs the body is read,
the connection is clean, and an ordinary response is possible.

**This Plug performs no cryptography.** The hook is named `:authorize_body` rather than
`:verify_signature` because verifying is the host's work; making it possible is this module's.

### Resources this Plug bounds, and the ones it does not

`@max_body_bytes` caps a single body at 1 MiB. Three things that is **not**:

- It is not an aggregate bound. Each in-flight request at the cap costs about 1.05 MiB, measured
  linear with no plateau to 8,000 concurrent (+8.16 GiB RSS). The concurrent-request ceiling is
  your HTTP server's: for `Bandit`/`ThousandIsland` it is `num_acceptors * num_connections`,
  defaulting to 100 × 16,384 = **1,638,400**. Setting it is the host's capacity decision, and a
  number this package picked for you would be one it cannot keep.
- It is not a ceiling on bytes read. What the **server** reads before refusing is the cap
  itself over HTTP/1: a declared 32 MiB body is refused after `read_body/2` returns a partial of exactly
  **1,048,576 bytes**, constant across six socket-buffer settings and four runs (over HTTP/2 the
  adapter hands whole frames, so the read is the cap plus the frame that crosses it, at most
  16 KiB — the threat model's row). How much the
  **client** got onto the wire by then is a different quantity and not a property of this
  package — the same 24 measurements put it between 1.125 MiB and 7.438 MiB, varying run to run
  at one fixed buffer size — so there is no number to design against there, only the
  server-side constant above.
- It is a time bound, and the bound is yours: `read_timeout:` (default 15,000 ms, a chosen
  number with its reasoning beside the constant) is one whole-body deadline, this package's own
  — the body is read in pieces against one clock, each read given what remains, so a drip client
  is answered `408` when it lapses, however many bytes arrived and however the adapter splits
  the reads (the adapter's own `:read_timeout` is a per-read clock: a cap-sized body is two
  adapter reads and got two deadlines, 1,909 ms for 1,000; over HTTP/2, which `Bandit` serves on
  the same listener, its reader gathers DATA frames on a per-frame clock and a
  one-byte-per-frame drip of a valid call was served after 20 s under a 300 ms deadline — both
  measured by review lanes, 2026-09-16, and both closed: over HTTP/2 the reader is asked for
  less than one frame, so every DATA frame, an empty one included, returns to this clock).
  Measured through a real `Bandit` listener: `408` at 300, 301, 327 ms for a 300 ms deadline
  and 1,500, 1,500, 1,501 ms for 1,500 ms; over HTTP/2 a twenty-frame drip answered at the
  deadline. One residue is the adapter's, stated on the threat model's row with its cost: over
  HTTP/2 a stream kept open by control frames alone (a WINDOW_UPDATE, or a HEADERS without
  END_STREAM) is held past the deadline by the adapter's own wait, which nothing outside it
  can end through an interface the adapter offers — one frame per deadline holds a stream
  process indefinitely, whatever body then comes is refused, a WINDOW_UPDATE costs thirteen
  bytes with nothing accumulated, and a HEADERS without END_STREAM writes a warning line per
  frame to the host's log carrying the client's header bytes. The stream is the adapter's to
  end, but the **connection** is this package's: `connection_timeout:` (default twice
  `read_timeout`) closes a connection whose body read has been held that long, with nothing
  else on it still within its own deadline, using a `GOAWAY` the client can read — so the
  residue is bounded in duration by this package and in count by `max_concurrent_streams`,
  and its cost is per connection (the client's other streams still open on it end with the
  `GOAWAY`; a host multiplexing long streams raises `connection_timeout`).
  The `408` is this package's refusal — the JSON-RPC error object
  every refusal carries, with `connection: close` over HTTP/1.1 as for every refusal issued
  before the body is read (over HTTP/2 the stream ends with the response; the header would be a
  malformed one there, and a client answered with it saw a stream reset in place of the refusal
  — measured, and closed for every pre-body refusal). Nothing is written to the host's log for a
  `408`: the adapter's own error-level line at its read timeout no longer fires, since the
  deadline is this package's. A body must declare its length: `transfer-encoding: chunked` is
  refused with `411` before the body is read, because the adapter reads a chunked body chunk by
  chunk on a per-chunk clock and a client sending one byte per chunk was served after 43 s under
  a 15 s deadline (a review lane, 2026-09-16) — an MCP request is one complete JSON message
  under the cap, and a chunked body defeats every whole-body bound; no MCP client this package
  has been run against sends one. For two releases this package passed no deadline at all, and
  the value in force was `Bandit`'s default for such a call, which the README called "inherited
  from the server"; it was neither a server option nor a choice.
- It does not bound **headers**. `@max_body_bytes` is a body limit; the number and size of
  request headers are your HTTP server's settings, as the read timeout was until it became
  `read_timeout:`.
- It bounds **nesting** separately. A body under the cap can still nest half its bytes deep,
  and decoding one that did cost a 38 MiB heap for one request (measured); so every body, on
  both transports, is refused by name past 64 levels of nesting before the decoder runs
  (`-32600`, `400`), and the per-request figure above stays the body's size.

Every vector on the wire — refused, bounded, or delegated to your HTTP server — with the
test that enforces each, is [`docs/threat-model.md`](docs/threat-model.md). Mount this Plug
ahead of `Plug.Parsers` or exclude its path: behind the parsers the body is already consumed
and every request is a parse error.

**A refusal issued before the body is read ends the connection, and says so.** The `Origin`
`403`, the `405`, `authorize/1`'s refusals and the body-cap `413` are all issued before this
Plug has read the request body, so each carries `connection: close`. Without it your server reads
that body anyway, on behalf of a caller this Plug has already refused — `Bandit` drains up to
8 MB, waiting up to its read timeout to do it — and past that it gives up and drops the
connection with nothing said to the client. A refusal issued *after* the body has been read
keeps the connection, because by then there is nothing left to drain. What this does not do is
get a pipelined second request answered: it cannot, and declining to read a refused caller's
body is the point.

`allowed_origins` is separate because the specification makes validating `Origin` a MUST, to
prevent DNS rebinding; which origins are legitimate is yours to say. `:any` is available and must
be chosen deliberately. The specification also says a locally-running server **SHOULD** bind to
localhost rather than all interfaces — that is your `Bandit` option, above, and this package
cannot enforce it for you.

**What the header requirement does and does not close.** The transport requires an
`MCP-Protocol-Version` header on every POST and requires it to match the body, so a request that
establishes no **protocol era** is malformed and refused — that part of the stdio caveat below
does not apply here.

It does not close the **lifecycle**. `tools/call` over HTTP runs without `initialize` having been
seen, because `2026-07-28` has no `initialize` and every request stands alone. That is the
revision's design rather than a gap, but an earlier draft of this section said "a request with no
era established is malformed and refused" in a way that read as covering both, and a reviewer was
right that it claimed more than the code supports. Who may call is `authorize/1`'s question, and
it is yours.

## What of `2026-07-28` this transport implements

Stated as a list rather than left to be inferred, because a transport that advertises a feature
and does not enforce it is worse than one that never advertised it.

**Implemented.** One POST endpoint; `MCP-Protocol-Version` required and matched against the
body's `params._meta`; `Mcp-Method`, `Mcp-Name` and `Mcp-Param-{Name}` required where the revision
requires them and validated against the corresponding body values; `=?base64?…?=` header values
decoded before comparison; `Origin` validated against a host-supplied allow list; a body size
bound; `405` on non-POST; `404` for an unimplemented method and `200` with a JSON-RPC error for
an unknown tool. Every header is checked in **all** of its values, not the first — a duplicated
header is the smuggling primitive the specification's validation MUST exists to prevent.

`Mcp-Param-{Name}` is enforced because `tool_definition/1` passes a schema's `x-mcp-header`
annotation through to `tools/list` verbatim. Advertising that a header is authoritative and then
ignoring it gives a client that believes you a silent divergence between the value it routed on
and the value that ran.

**An `x-mcp-header` annotation the specification forbids is the host's fault, not the caller's.**
The revision allows the annotation only on primitive parameters — integer, string, boolean — and
requires its values to be case-insensitively unique. A schema breaking either is refused,
`500` with `-32603`, and the diagnosis names the tool and the offending annotation in the log.
Nothing about it reaches the caller: the request was well formed and it is the server that is
misconfigured. Every call to that tool is refused until the schema is corrected, rather than a
subset of what `tools/list` advertised being enforced silently. A property with **no** declared
type is left alone, because it cannot be judged from the schema and judging it on the caller's
value instead would turn a wrong-shaped request into a host fault.

**Not implemented, by design of the revision.** Sessions, `Mcp-Session-Id`, SSE streaming, and
SSE resumability — all removed from this revision's transport; and the `initialize` /
`notifications/initialized` handshake, which `2026-07-28` deleted along with `ping`.

Those three are **refused** here rather than merely absent: `404` with `-32601`. The distinction
is not pedantry. The package's core is dual-era and its `initialize` clause deliberately
outranks `_meta`, because over stdio an `initialize` *is* the era discriminator — so before this
was refused at the transport, an HTTP caller declaring `2026-07-28` could send `initialize` and
receive `200` with `protocolVersion: "2025-11-25"`, a different revision's version number, while
this section said it was not implemented. The refusal lives in the transport and not in the core
because HTTP is the carrier that stamps every request modern; stdio's dual-era rule is untouched.

**Not implemented, and yours.** Binding to localhost (a `Bandit` option), TLS, request timeouts
and connection limits (your HTTP server's settings, not this Plug's), and authentication —
`authorize/1` is where you put it, and it is required precisely so the decision is yours.

## What it speaks

Newline-delimited JSON-RPC over stdio, **dual-era**: it serves both the current revision and
one legacy revision.

| | `2026-07-28` (modern) | `2025-11-25` (legacy) |
|---|---|---|
| opens with | any request, or `server/discover` | `initialize`, or `_meta` naming it |
| version travels in | `params._meta` on every request | the `initialize` params, or `params._meta` |
| session | none; each request stands alone | tracked, not enforced — see below |
| `ping` | removed from the revision, refused | answered |
| result envelope | `resultType` and `_meta` `serverInfo` | neither; both are `2026-07-28` additions |

`server/discover`, `tools/list`, `resources/list`, `resources/templates/list`, `resources/read`,
`prompts/list`, `prompts/get`, `tools/call`, `shutdown`, `exit` at both eras; `initialize` and
`notifications/initialized` at legacy only.

**A revision, not a carrier, decides the semantics.** `params._meta` — the request's `_meta`
lives inside `params`, the schema's one position; a `_meta` at the top level of the request is
refused as invalid params, not read as a fallback — decides only that a request is served
statelessly. Which revision it *names* then decides the method table and the
result envelope, so a `ping` declaring `2025-11-25` through `_meta` is answered and its result
carries no `resultType`. This matters because `-32022` tells a client to pick from `supported`
— which lists `2025-11-25` — and retry the request, so a `_meta` naming the legacy revision is
a message this server asks clients to send.

**Two exceptions, and they are exceptions to the row above.** `server/discover` and
`initialize` are matched *before* the revision switch, so neither is affected by what a `_meta`
declares. `server/discover` is matched first on purpose: **on stdio it is the era probe**, sent
by a client that does not yet know what it is talking to, and it is answered bare. Its result
is the `2026-07-28` `DiscoverResult` in full — `supportedVersions`, `capabilities`,
`resultType`, `ttlMs`, `cacheScope`, and the server's identity in `_meta` — because a client
reading a bare result has grounds to classify the server as legacy. `initialize` is the
legacy opener and its result is legacy-shaped. **Over HTTP there is no era probe:** every
POST must carry `mcp-protocol-version`, a headerless `server/discover` is refused like any
other request, and the transport advertises only the revision it serves — `supportedVersions`
is `["2026-07-28"]` there. Dual-era is a stdio fact.

**The session is tracked, not enforced.** Nothing in this package refuses a request because
`initialize` has not been seen: every method it implements is served bare, `tools/call`
included — and `tools/call` executes through the host's dispatch. On stdio that is defensible,
because whoever can write to the transport already has the host's privileges. **On any
transport where that is not true, refusing unestablished callers is the host's job, and this
package does not do it for you.**

A request naming a revision the server does not support gets `UnsupportedProtocolVersionError`
(**`-32022`**) listing what it does support. **`2024-11-05` is not supported** — it predates
the two chosen revisions.

**JSON-RPC batching is refused.** It was added in `2025-03-26` and removed in `2025-06-18`, so
it is required by exactly one revision of five and by neither of ours.

## Conformance, as two rows

Measured against the official MCP conformance suite, `@modelcontextprotocol/conformance`
**0.2.0-alpha.11** (pinned by exact version in `tools/conformance.sh`; the npm `latest` line has
no `2026-07-28` scenarios), with each revision's frozen requirement set (`--requirements`),
against this package's HTTP transport on Bandit with the harness catalog in
`conformance/server.exs`. Both rows come from the suite's own `checks.json` and are never
typed; both ship together or neither does.

| revision | suite totals (scored server scenarios) | claimed-surface totals | measured |
| -- | -- | -- | -- |
| `2026-07-28` | **16 / 37** | **5 / 6** — `server-stateless`: 21 of 30 checks pass, 5 are skipped (no subscription capability, by decision), 4 need diagnostic tools this harness does not invent | 2026-09-15, `tools/conformance.sh` |
| `2025-11-25` over HTTP | **0 / 30** | 0 / 5 | 2026-09-15, `tools/conformance.sh` |

**Suite totals do not hide the failures.** The twenty-one `2026-07-28` failures are surfaces
this package holds out by decision — completion, content types beyond text, progress
notifications — and scenarios that need diagnostic tools this harness does not invent
(subscriptions are skipped checks, not failures), each named with its reason word in
`conformance/baseline-2026-07-28.yml`; the
suite exits 1 on a regression *or* on a baselined scenario that starts passing (the resource
and prompt scenarios left the file the day they passed). A scenario passes when none of its checks is `FAILURE` or `WARNING` —
the suite's rule under `--expected-failures`, which ticks two fewer scored scenarios than
its plain console summary. **Claimed-surface totals** count only the six scenarios named
in `conformance/README.md`: `server/discover` and the stateless rules, `tools/list`,
`tools/call` with text content and tool errors, the origin rules, concurrent POSTs.
**The `2025-11-25` row is the design meeting the suite, not a failure:** the HTTP transport
serves `2026-07-28` only, and `2025-11-25` lives on stdio, which the suite cannot drive (it
has no stdio server mode). `conformance/README.md` has the rest.

**Reproduce it:** `tools/conformance.sh` — one command, for anyone with Node ≥ 22 and
`python3`. **The trade, stated:** this package has two dependencies; producing this number
costs a second toolchain, so the step runs in a CI job of its own (`conformance.yml`, Node 22
pinned) and never in the local gate, which stays the fifteen steps a contributor with Elixir
and Erlang runs green with nothing else installed (Dialyzer among them, on the OTP binary — its
PLT is built once per machine, about a minute, and kept under `_build`). The gate needs hex.pm (two steps resolve
dependencies); of those, the dependency audit is the one that refuses an answer hex gives
without reaching the registry — it says NOT MEASURED rather than passing from the cache, and
CI requires the measurement. The CI job fails loudly when the toolchain is absent; it never
skips.

## The connectome

The package exports a composed system's call graph — its wiring diagram — twice, and diffs the
two. Every export is canonical JSON that names the digest it is hashed with — SHA-256 unless
the host chooses SHA-384 or SHA-512 by option — so the same graph gives the same bytes whoever
wrote it, and a verifier reads the algorithm from the bytes
([`docs/connectome-canonical.md`](docs/connectome-canonical.md); the package's whole
cryptographic posture, and what a FIPS-mode host needs from it, are
[`docs/crypto-posture.md`](docs/crypto-posture.md) and [`docs/fips.md`](docs/fips.md)).

- **Declared** — `BeamMCP.Connectome.Declared.build/1` reads what *can* happen: the catalog,
  the call edges of the modules in scope from their beams (OTP's `:xref`), and a grouping of
  modules by OTP application. Beside the graph it returns a completeness bound: every dynamic
  dispatch site, callee outside the scope and unreadable entry, enumerated rather than guessed.
- **Observed** — `BeamMCP.Connectome.Observed` reads what *did* happen: a `:telemetry` span on
  the one dispatch site and a host-started ETS collector, plus an optional, off-by-default,
  guarded tracer for module-level edges (`BeamMCP.Connectome.Tracer`). Edge identity only —
  never a payload byte. The collector's per-call cost is measured and gated at 1.5 µs per
  `tools/call` — the owner's ceiling, set 2026-09-14 with its reasoning in `bench/overhead.exs`;
  a ceiling on an optional feature and not a performance promise.
- **Canonical bytes** — `BeamMCP.Connectome.Canonical` writes RFC 8785-style key order, NFC
  strings and one float rule, specified in [`docs/connectome-canonical.md`](docs/connectome-canonical.md)
  completely enough that three blind re-derivations reproduced the hash.
- **The diff** — `BeamMCP.Connectome.Diff.run/3` puts every edge of either graph in exactly
  one of four classes — declared and observed, declared and never observed (dead authority),
  observed but undeclared (a drift finding), changed sign — with ten coverage counts the
  consumer divides. [`docs/connectome-diff.md`](docs/connectome-diff.md).

**On the wire, as a host chooses.** `BeamMCP.Connectome.Surface` gives a host three read-only
resources — `connectome://declared`, `connectome://observed`, `connectome://diff` — to put in
its own catalog, and `call/2` for the one `:observe` tool a host that exposes tools only
writes itself (the package holds no tool; the spec to copy is in the moduledoc); each answers
the canonical bytes, byte-identical to the file export (the tool carries them verbatim under
`bytes` with their hash beside, keyed by the algorithm's name — `sha256` unless the host's
`algorithm:` says otherwise), and nothing else. The host's `read_resource/1` and
dispatch delegate to `read/2` and `call/2` with the builder's options, the collector's name
and the consumer's window. Read-only by construction and by test: the package's state is
compared term for term before and after a call (the tool's own call is a dispatch, which a
running collector records like any other — the moduledoc says so). Nothing else on the wire
moves when a host adds them — a recording of the five advertising methods, on the core (what
stdio writes) and through the HTTP transport, before and after, differs by exactly the
entries.

**What it never does.** It populates no sign — `:allow`, `:deny`, `:hold` and `:ungoverned` are
a consumer's to write, and the package writes only `:unset` — signs no finding, holds no key and decides
no authority; a census test over `lib/` holds that. It claims no MCP capability the
specification does not define: neither protocol revision has a topology primitive, so nothing
on the wire changes and no capability is invented — `connectome://` is a URI scheme of this
package's own, served by the resources primitive like any other resource.

[`livebooks/connectome.livemd`](https://github.com/ScriptKittyOS/beam_mcp/blob/main/livebooks/connectome.livemd) renders the declared graph, the
observed graph with its weights and the diff, from the JSON export alone — it installs Kino
and a JSON decoder and no `beam_mcp`, so a reader with only the export sees what a reader
with the package sees. The vocabulary is in [`docs/connectome.md`](docs/connectome.md); the
collector, the tracer and its stated threat model in
[`docs/connectome-observed.md`](docs/connectome-observed.md).

## What this package is, and is not

**Shipping now.** The protocol core for `2026-07-28` and `2025-11-25`; the stdio and stateless
Streamable HTTP transports; JSON Schema validation of tool arguments; the catalog contract —
tools, resources and prompts declared by the host (`BeamMCP.ToolSpec`, `BeamMCP.ResourceSpec`
and `BeamMCP.ResourceTemplateSpec`, `BeamMCP.PromptSpec`), tools dispatched through the host's
function, resources read and prompts rendered through its two optional callbacks, the resource
and prompt lists paginated by one keyset cursor (`BeamMCP.Cursor`; `tools/list` is not yet);
the connectome spine above — declared, observed, canonical bytes, diff — with the Livebook
that renders it and the read-only surface a host puts on the wire
(`BeamMCP.Connectome.Surface`); and reachability queries over a graph
(`BeamMCP.Connectome.Reach`: can an entry reach an effect, can it do so without crossing a
gate — with a witness path made of the graph's own edges — does a gate dominate an effect, and
which nodes every path must cross; on OTP's `:digraph`, dominators by Lengauer–Tarjan, no new
dependency; [`docs/connectome-reach.md`](docs/connectome-reach.md)). Every module named in
this paragraph is held by a census to the set compiled from `lib/`, and any module named in
the three paragraphs below is held absent from it (none names one today).

**Decided and not built.** Settled by an owner decision, with no code behind it yet: a
federation seam for merging graphs from several nodes; and effective connectivity, the
observed graph weighted into the declared one. Multi-round-trip requests are decided
*against* ([`docs/will-not-implement.md`](docs/will-not-implement.md), entry 12).

**Scheduled.** In that order, each at the minor position while the package is `0.x`: the
federation seam, then effective connectivity.
`1.0.0` follows once the public API and the stated threat model have each survived a full
minor release unchanged. Who decides, how a change lands, and what happens if the one
maintainer stops: [`docs/governance.md`](docs/governance.md) and
[`docs/succession.md`](docs/succession.md), stated as they are.

**Deliberately out.** Tools, domain and policy; risk tiers, approvals, receipts and egress
masking; authority — the verdict on an edge, the key that signs it, the decision that acts on
it. These are absent by decision, not by immaturity: they live on the consumer's side of a
boundary this project chose on its first day, and the package exists partly to keep them
there. A small surface can look unfinished from the outside; this one is a commodity layer
that says which it is. The list is derived, not typed: the thesis sentence at the top of this
README, the census test that no line under `lib/` writes a sign other than `:unset`, and a
test that no line under `lib/` names a receipt, an approval, a risk tier or egress. The full
boundary — twelve entries, each with the test that enforces it by path and by name — is
[`docs/will-not-implement.md`](docs/will-not-implement.md), held to the tests in both
directions by a census of its own; a request to cross it is answered by pointing there. What
the package defends against on the wire, and what it hands to the server or the host, is
[`docs/threat-model.md`](docs/threat-model.md), held the same way.

## Status

Pre-1.0. The API may change. Known gaps are listed above and in
[`CONVENTIONS.md`](https://github.com/ScriptKittyOS/beam_mcp/blob/main/CONVENTIONS.md), which is
not shipped in the package and so is linked rather than named. It also
records how this package is developed — the gate takes no baseline, a probe's population is
derived the way the checked mechanism derives it, and CI is unproven until a run exists.

Consumers today: Ultraviolet, and Trinity as a candidate under its own evaluation.

## Licence

Apache-2.0. See `LICENSE`, and `NOTICE` for attribution.

## Export control

A plain-language statement for the compliance reader, of fact where it is about this package
and of the maintainer's reading where it is about the regulations. **It is not legal advice,
and it has not been reviewed by counsel** — that sentence leaves this paragraph only when one
has.

`beam_mcp` is open-source software, published publicly under the Apache License 2.0 on GitHub
and on hex.pm. **Its own code contains no encryption.** Its only cryptographic operation is a
SHA-2 message digest — SHA-256 by default, SHA-384 or SHA-512 by option — computed by
Erlang/OTP's `:crypto` (OpenSSL on the builds the maintainers run) at one call site, used
solely for integrity hashing of canonical bytes ([`docs/crypto-posture.md`](docs/crypto-posture.md));
it holds no key material, and a census in its test suite refuses any other `:crypto.` call
and any key by name. The optional HTTP transport's dependencies (`plug`, `bandit`) bring their
own libraries — `plug_crypto` carries AES — into an integrator's build; those are outside this
package's tarball and are the integrator's classification, as the last sentence says. Under **15 CFR 734.7(a)(4)**, unclassified
software made available to the public without restriction — "posting on the Internet on
sites available to the public" — is published and thus not subject to the Export
Administration Regulations; the exception in **734.7(b)** for published *encryption* software
classified under ECCN 5D002 (which, with **742.15(b)**, keeps such software subject to the EAR
unless its source is publicly available and, for "non-standard cryptography", notified) does
not reach a library whose only cryptographic function is a standard message digest — the
maintainer's reading; the regulation's own definitions (15 CFR 772.1) limit "cryptography" to
transformations using "secret parameters" and "encryption software" to programs that provide
"encryption functions or confidentiality of information", and an unkeyed digest is neither. This software is not
designed for any article on the United States Munitions List, and no commodity-jurisdiction
determination has been sought for it; whether it is ITAR-controlled is a classification
conclusion this paragraph does not make. Downstream integrators remain responsible for the
export classification of the products that incorporate it.
