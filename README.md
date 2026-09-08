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
  [{:beam_mcp, "~> 0.3.0"}]
end
```

**`~> 0.3.0`, not the more usual `~> 0.3`.** While this package is `0.x` it documents wire
breaks at the **minor** position, and it has used that position twice: `0.2.0` removed two
fields from results for legacy-declared requests, and `0.3.0` adds the HTTP transport and the
`ttlMs`/`cacheScope` fields `2026-07-28` requires on `tools/list`. `~> 0.3` admits `0.4.0`, so
it would carry you across the next such break on a routine `mix deps.update`; `~> 0.3.0` does
not. The tighter form is deliberate and is not an over-pin to be tidied away.

## Two contracts

Injection without a specification is a claim with nothing behind it, so both are declared.

**`BeamMCP.ToolCatalog`** — the host names the tools.

```elixir
defmodule MyApp.Catalog do
  @behaviour BeamMCP.ToolCatalog

  @impl true
  def all do
    [
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
  end
end
```

**The dispatch callback** — the host does the work.

```elixir
@type dispatch :: (atom(), map(), keyword() -> {:ok, term()} | {:error, term()})
```

## Running it

```elixir
BeamMCP.Transport.Stdio.run(
  tool_catalog: MyApp.Catalog,
  dispatch: &MyApp.Dispatch.call/3,
  server_name: "my-app"
)
```

`:tool_catalog` is required. `:dispatch` is required for `tools/call`. `:server_name` defaults
to `beam_mcp`, and a host that wants its own name in `initialize` says so.

## One schema, one source

A tool's schema lives on its `ToolSpec`. `tools/list` advertises **that** schema and
`tools/call` enforces **that** schema, so the contract a client is shown and the contract it is
held to cannot drift apart. Argument keys are derived from the schema's `properties` and reach
`dispatch` as **atoms** — a tool declaring `"place"` is dispatched `%{place: "Oslo"}`, not
`%{"place" => "Oslo"}`. Values are passed through unchanged, because turning a string into a
domain term is the host's job and a generic layer that guesses has acquired someone else's
domain.

A `ToolSpec` that omits `input_schema` is a tool with no arguments: it advertises an open
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
         tool_catalog: MyApp.Catalog,
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
      tool_catalog: MyApp.Catalog,
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
already in the adapter's buffer, and a larger one hangs until the server's read timeout and then
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

**This package performs no cryptography.** The hook is named `:authorize_body` rather than
`:verify_signature` because verifying is the host's work; making it possible is this module's.

### Resources this Plug bounds, and the ones it does not

`@max_body_bytes` caps a single body at 1 MiB. Three things that is **not**:

- It is not an aggregate bound. Each in-flight request at the cap costs about 1.05 MiB, measured
  linear with no plateau to 8,000 concurrent (+8.16 GiB RSS). The concurrent-request ceiling is
  your HTTP server's: for `Bandit`/`ThousandIsland` it is `num_acceptors * num_connections`,
  defaulting to 100 × 16,384 = **1,638,400**. Setting it is the host's capacity decision, and a
  number this package picked for you would be one it cannot keep.
- It is not a ceiling on bytes read. What the **server** reads before refusing is the cap
  itself: a declared 32 MiB body is refused after `read_body/2` returns a partial of exactly
  **1,048,576 bytes**, constant across six socket-buffer settings and four runs. How much the
  **client** got onto the wire by then is a different quantity and not a property of this
  package — the same 24 measurements put it between 1.125 MiB and 7.438 MiB, varying run to run
  at one fixed buffer size — so there is no number to design against there, only the
  server-side constant above.
- It is not a time bound. A slow client is held by `read_body/2`'s `:read_timeout`, which this
  package does not set and therefore inherits from the server — 15,000 ms under `Bandit`. That is
  a whole-body deadline rather than a per-read reset, so a drip client is answered `408` at 15 s
  rather than held indefinitely. That makes slow connections a **transient** rather than a hold:
  they cost memory for at most the timeout, and a legitimate request was still served in under
  0.01 s with 12,000 of them in flight.

- It does not bound **headers**. `@max_body_bytes` is a body limit; the number and size of
  request headers are your HTTP server's settings, inherited the same way the read timeout is.

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
body's `_meta`; `Mcp-Method`, `Mcp-Name` and `Mcp-Param-{Name}` required where the revision
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
| version travels in | `_meta` on every request | the `initialize` params, or `_meta` |
| session | none; each request stands alone | tracked, not enforced — see below |
| `ping` | removed from the revision, refused | answered |
| result envelope | `resultType` and `_meta` `serverInfo` | neither; both are `2026-07-28` additions |

`server/discover`, `tools/list`, `tools/call`, `shutdown`, `exit` at both eras; `initialize`
and `notifications/initialized` at legacy only.

**A revision, not a carrier, decides the semantics.** `_meta` decides only that a request is
served statelessly. Which revision the `_meta` *names* then decides the method table and the
result envelope, so a `ping` declaring `2025-11-25` through `_meta` is answered and its result
carries no `resultType`. This matters because `-32022` tells a client to pick from `supported`
— which lists `2025-11-25` — and retry the request, so a `_meta` naming the legacy revision is
a message this server asks clients to send.

**Two exceptions, and they are exceptions to the row above.** `server/discover` and
`initialize` are matched *before* the revision switch, so neither is affected by what a `_meta`
declares and **neither result is decorated** — a `server/discover` result carries no
`resultType` even under `2026-07-28`, where the specification requires one on every result.
`server/discover` is matched first on purpose: on stdio it is the era probe, sent by a client
that does not yet know what it is talking to. The missing `resultType` on it is a known gap,
not a design choice.

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

## Status

Pre-1.0. The API may change. Known gaps are listed above and in
[`CONVENTIONS.md`](https://github.com/ScriptKittyOS/beam_mcp/blob/main/CONVENTIONS.md), which is
not shipped in the package and so is linked rather than named. It also
records how this package is developed — the gate takes no baseline, a probe's population is
derived the way the checked mechanism derives it, and CI is unproven until a run exists.

Consumers today: Ultraviolet, and Trinity as a candidate under its own evaluation.

## Licence

Apache-2.0. See `LICENSE`, and `NOTICE` for attribution.
