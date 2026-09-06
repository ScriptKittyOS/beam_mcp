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

Validation is a deliberately small subset of JSON Schema — `type`, `properties`, `required`,
`additionalProperties`, and bounds. It refuses rather than guesses, and it is not a general
validator.

## What it speaks

`initialize`, `notifications/initialized`, `ping`, `tools/list`, `tools/call`, `shutdown`,
`exit`. Protocol revision **`2024-11-05`**, newline-delimited JSON-RPC over stdio.

**Revision negotiation is not implemented.** The server advertises one revision and does not
negotiate; a client asking for another gets this one. That is the next piece of work, and it
is stated here rather than discovered by a reader.

## Status

Pre-1.0. The API may change. Known gaps are listed above and in `CONVENTIONS.md`, which also
records how this package is developed — the gate takes no baseline, a probe's population is
derived the way the checked mechanism derives it, and CI is unproven until a run exists.

Consumers today: Ultraviolet, and Trinity as a candidate under its own evaluation.

## Licence

Apache-2.0. See `LICENSE`, and `NOTICE` for attribution.
