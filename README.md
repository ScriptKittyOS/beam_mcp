<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# BeamMCP

A Model Context Protocol server core for the BEAM. Protocol handling, a stdio transport, and
JSON Schema validation — with the tool catalog and the dispatch function injected by the host.

The package holds no tools, no domain, and no policy. It decides what a well-formed request is
and refuses one that is not; what a tool *does* is the host's business.

```elixir
def deps do
  [{:beam_mcp, "~> 0.1"}]
end
```

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
held to cannot drift apart. Argument keys are derived from the schema's `properties`; values
are passed through unchanged, because turning a string into a domain term is the host's job and
a generic layer that guesses has acquired someone else's domain.

A `ToolSpec` that omits `input_schema` is a tool with no arguments: it advertises an open
empty object, so `tools/call` refuses nothing and dispatch is handed `%{}` whatever the client
sent.

Validation is a deliberately small subset of JSON Schema — `type`, `properties`, `required`,
`additionalProperties`, and bounds. It refuses rather than guesses, and it is not a general
validator.

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

Pre-1.0. The API may change. Known gaps are listed above and in `CONVENTIONS.md`, which also
records how this package is developed — the gate takes no baseline, a probe's population is
derived the way the checked mechanism derives it, and CI is unproven until a run exists.

Consumers today: Ultraviolet, and Trinity as a candidate under its own evaluation.

## Licence

Apache-2.0. See `LICENSE`, and `NOTICE` for attribution.
