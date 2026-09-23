<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Architecture

The high-level design: the parts of the package, what each one owns, how a request moves
through them, and the properties the arrangement is built to keep. Each module's own
documentation is the detail; this page is the map.

## The shape in one paragraph

A **transport** reads bytes from a client under a bound and decodes them through one JSON
reader; the **protocol core** turns one decoded message into one response, consulting the
**catalog** the host supplied and calling the **dispatch** function the host supplied; the
transport writes the response back. The core holds no process and no state between
requests. Beside that path sits the **connectome**: a description of what a composed system
can reach (declared) and what it did reach (observed), with canonical bytes a consumer can
hash and sign. The host owns everything that decides or acts; the package owns the wire.

```text
   client bytes
        |
        v
 +------------------+      +------------------+
 | Transport.Stdio  |  or  | Transport.HTTP   |   read under a bound; Origin, headers,
 | (line or frame)  |      | (a Plug)         |   deadlines; host authorize hooks
 +--------+---------+      +---------+--------+
          |                          |
          +-----------+--------------+
                      v
              BeamMCP.JSON          nesting bound, repeated keys, then Jason
                      |
                      v
              :server module        BeamMCP.Server by default; a host wrapper may sit above it
                      |
                      v
              BeamMCP.Server        one message in, one response out, no process, no state
               |      |      |
               |      |      +--> BeamMCP.Cursor      (keyset pagination for every list)
               |      +---------> BeamMCP.Schema      (tool arguments vs the advertised schema)
               +----------------> host's Catalog      (capabilities/0, read_resource/1, get_prompt/2)
                                  host's dispatch     (tools/call, after validation)
```

## The parts

**Transports** (`BeamMCP.Transport.Stdio`, `BeamMCP.Transport.HTTP`). Stdio reads
newline-delimited JSON-RPC, with the older `Content-Length` framing accepted, each line or
frame under a 1 MiB bound. HTTP is a stateless Streamable HTTP `Plug` for the `2026-07-28`
revision: no sessions, one endpoint, the body read under the same cap and a whole-body
deadline, `Origin` checked against a list the host must give, and every `Mcp-*` header held
to the body. HTTP is optional: `plug` and `bandit` are optional dependencies, and a stdio-only
host compiles without them. A transport owns bytes and framing and nothing about the protocol.

**The JSON reader** (`BeamMCP.JSON`). The one place wire JSON is decoded, on both transports.
It walks the bytes once to refuse nesting past 64 levels before the decoder runs, then refuses
an object that repeats a key. Everything downstream sees plain maps, lists, strings and
numbers.

**The protocol core** (`BeamMCP.Server`). `new/1` validates the host's configuration once,
at startup; `handle_message/2` answers one message. It speaks two protocol revisions,
`2026-07-28` and `2025-11-25`, and answers each request in the revision the request declared.
It is a behaviour as well as the default module, so a host can place a wrapper above it
through the transports' `:server` option without the transports changing.

**The host contracts** (`BeamMCP.Catalog`, the dispatch function). The host declares tools,
resources, resource templates and prompts through `c:BeamMCP.Catalog.capabilities/0`, as
`BeamMCP.ToolSpec`, `BeamMCP.ResourceSpec`, `BeamMCP.ResourceTemplateSpec` and
`BeamMCP.PromptSpec` (with `BeamMCP.PromptArgument`) structs. The same declaration is what
`*/list` advertises and what `tools/call`, `resources/read` and `prompts/get` accept, so an
advertised item and a callable item cannot disagree. Dispatch is a function the host passes;
the package never executes a tool.

**Validation and pagination** (`BeamMCP.Schema`, `BeamMCP.Cursor`). `BeamMCP.Schema` checks
`tools/call` arguments against the schema the catalog advertised, before dispatch; a prompt's
arguments are derived into the same kind of schema and checked the same way.
`BeamMCP.Cursor` is the one keyset cursor every paginated list shares.

**Fault hygiene** (`BeamMCP.Stacktrace`). Wherever a stacktrace leaves the package (a
telemetry event, a transport's fault log) its argument lists are replaced by their lengths,
so a caller's bytes do not travel in an error.

**The connectome** (the modules under `lib/beam_mcp/connectome/`). A graph of what talks
to what: `BeamMCP.Connectome.Node`, `BeamMCP.Connectome.Edge` and
`BeamMCP.Connectome.Graph` are the data model; `BeamMCP.Connectome.Declared` builds the graph from what the host declares;
`BeamMCP.Connectome.Observed` (a collector the host starts) and
`BeamMCP.Connectome.Tracer` (opt-in, bounded, off by default) record what ran;
`BeamMCP.Connectome.Diff` compares the two; `BeamMCP.Connectome.Reach` answers reachability
questions (can an entry reach an effect without crossing a gate);
`BeamMCP.Connectome.Canonical` writes the canonical bytes and their SHA-2 digest, specified
in `docs/connectome-canonical.md` so a verifier can be written in another language; and
`BeamMCP.Connectome.Surface` is the read-only view a host may put on the wire.

**The signer seam** (`BeamMCP.Signer`, `BeamMCP.Signer.None`). The one place a signature can
enter: bytes in, signature out. The package's only implementation signs nothing. A signer
that holds a key is the separate package `beam_mcp_signer`, which the host attaches; this
package never depends on it.

## Properties the arrangement keeps

- **The core is a function.** No process, no state between requests, no session: each request
  is checked in full, and there is nothing for a client to steal or replay.
- **One mechanism per concern.** One JSON reader for both transports, one declaration for
  advertise and accept, one cursor for every list, one digest site. Two paths that could
  disagree are the defect this avoids.
- **Bounded by default.** Body size, nesting depth, read and connection deadlines, and the
  tracer's limits are all finite, and the tracer and the collector run only when a host starts
  them.
- **Authority stays with the host.** The package holds no tool, no key, no verdict and no
  client connection. `docs/will-not-implement.md` lists each absence with the census test that
  holds it; `test/beam_mcp/boundary/` is where those censuses live.
- **The public surface is pinned.** `docs/public-api.txt` lists every public function and
  type, and a census compares the compiled package against it on every run
  (`docs/api-stability.md`).

## Where to read next

- `docs/threat-model.md`: what each part defends against, vector by vector, with its test.
- `docs/assurance-case.md`: why the security requirements are met, argued from the above.
- `docs/connectome.md`: the connectome's vocabulary.
- The moduledoc of each module above, on hexdocs.
