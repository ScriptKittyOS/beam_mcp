<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# beam_mcp — PLAN

**Repository:** `github.com/ScriptKittyOS/beam_mcp` (transferred from `HackTuah` 2026-09-06;
the old path still resolves by redirect). Private, empty at start -- `main` had no commits.
**Spec of record:** the Linear project `beam_mcp` description, which **outranks the terminal
brief where they differ**. Divergences are recorded in `FINDINGS.md`.
**Source:** Ultraviolet `origin/main` = `778accb82759d3def30b2e1410e1aeb573f76dac`.
**Authorised:** owner, 2026-09-06, by enumeration. Written before any code, per the practice
carried from Ultraviolet's §3. This is **not** a slice in that tree; it is a new tree with its
own PLAN and its own gates.

## What this package is

The MCP protocol core, extracted so it can be used without Ultraviolet's domain. Apache-2.0
from commit 1. Package name `beam_mcp`. Namespace `BeamMCP`.

## Scope, fixed by the owner

**Travels:** `server.ex` (protocol core), `stdio.ex` (transport), `schema.ex` (generic
validation only), `tool_spec.ex`.

**Stays in Ultraviolet:** `dispatch.ex`, `tool_catalog.ex` (the concrete catalog),
`egress.ex`, and the boundary test asserting the non-read set is exactly `{propose_action}`.

**Never in the package:** risk tiers, approvals, receipts, masking, authority.

| Ultraviolet | beam_mcp |
|---|---|
| `HacktuiAgent.MCP.Server` | `BeamMCP.Server` |
| `HacktuiAgent.MCP.Stdio` | `BeamMCP.Transport.Stdio` |
| `HacktuiAgent.MCP.Schema` | `BeamMCP.Schema` |
| `HacktuiAgent.MCP.ToolSpec` | `BeamMCP.ToolSpec` |
| — (new) | `BeamMCP.ToolCatalog` (behaviour) |

Only external dependency: `jason`. Measured — `server.ex` and `stdio.ex` reference `Jason`;
`schema.ex` and `tool_spec.ex` reference nothing outside themselves.

## The two contracts the package must define

Injection without a specification is a claim with nothing behind it. So:

1. **A dispatch callback type** that Ultraviolet's `Dispatch.safe_call/3` matches:
   `@type dispatch :: (atom(), map(), keyword() -> {:ok, term()} | {:error, term()})`.
   `safe_call/3` is specced `(atom(), term(), keyword()) :: {:ok, term()} | {:error, term()}`,
   so it satisfies the callback; the package's type is the narrower, published one.
2. **A `BeamMCP.ToolCatalog` behaviour** — `@callback all() :: [BeamMCP.ToolSpec.t()]` — which
   Ultraviolet's concrete catalog implements.

## The demonstration that the seam is currently nominal

`server.ex:23-31` takes `:tool_catalog` and defaults it. `tools/list` at `:56-57` honours the
injected catalog: `Enum.map(state.tool_catalog.all(), &tool_definition/1)`. But
`normalize_tool_name/1` at `:144-153` calls `ToolCatalog.all()` **directly**, ignoring the
injection entirely.

So an injected catalog is honoured when **advertising** a tool and ignored when **calling** it.
The existing test passes only because `FakeToolCatalog`'s two tools are both present in the
real catalog as well. That coincidence is what commit 2 removes.

## Three commits, each proven before the next

### Commit 1 — the move, behaviour-preserving

Four files, module renames only. Both test runs pasted with pass counts and exit codes.
**If a test needs a substantive edit to pass, stop and report; do not edit it.**

**One unavoidable source change, declared rather than smuggled:** the package cannot default
`:dispatch` to `HacktuiAgent.MCP.Dispatch.safe_call/3` or `:tool_catalog` to
`HacktuiAgent.MCP.ToolCatalog` — those are exactly the modules that stay behind. The defaults
are therefore dropped and both become required injection. This is a **behaviour change for a
caller that omits them** and is not a rename. It changes no test: all four server tests inject
`tool_catalog:`, and the three that omit `dispatch:` never reach a dispatch. Ultraviolet's
production path (`Stdio.run/1` -> `Server.new(opts)`) supplies them in the path-dep PR.

**Travelling tests** (measured by what they reference):
- `hacktui_agent_mcp_server_test.exs` (4 tests) -> `test/beam_mcp/server_test.exs`

**Staying tests:** `mcp_boundary_test.exs` (references `Egress`), `mcp_dispatch_safety_test.exs`
(references `Dispatch`), and -- **corrected after reading it** -- `mcp_stdio_framing_test.exs`.

**PLAN correction, recorded not quietly fixed.** The first draft of this PLAN listed
`mcp_stdio_framing_test.exs` as travelling, on the strength of a grep showing it references
only `Stdio`. Reading it refutes that: it is an **end-to-end test that drives the real
`bin/hacktui-mcp` binary**, computes `repo_root()` as the umbrella root, runs `mix compile`
there in `setup_all`, and is tagged `:mcp_e2e`. Making it run in this package would require
a package-local launcher -- a substantive edit, which the owner's rule forbids in commit 1.
It stays.

**Consequence, reported rather than papered over:** `stdio.ex` travels with **no test coverage
in this package**. Its only test is bound to Ultraviolet's launcher. Closing that gap needs a
transport test written against `BeamMCP.Transport.Stdio` directly, which is new work and is
not commit 1.

### Commit 2 — catalog injection fixed, red first

Inject a catalog holding **one tool the real catalog lacks**; assert `tools/call` reaches
dispatch. It fails today, because `normalize_tool_name/1` consults the real catalog. Red
recorded verbatim before the fix.

### Commit 3 — schema onto ToolSpec, red first

Construct a `ToolSpec` carrying a schema the server has never seen; assert validation uses it.
The per-tool `input_schema/1` clauses (`server.ex:223-299`) and the argument normalisation
(`:186-217`) are Ultraviolet's domain data sitting in a generic module.

**The spec settles where they go**, and is more specific than the terminal brief's "neither
travel nor stay": *"the per-tool input schemas and argument normalisation currently welded into
`server.ex`, **which move onto `ToolSpec`**."* So the mechanism becomes generic in the package
and the data becomes catalog data carried on `ToolSpec` -- **argument normalisation moves with
the schemas** rather than remaining in `server.ex`. The design question this PLAN previously
raised is answered by the spec and is closed.

## Licensing, from commit 1

Apache-2.0. SPDX headers on every source file, REUSE-compliant (`LICENSES/Apache-2.0.txt`).
**DCO sign-off in the owner's name** (`git commit -s`). **No `Co-Authored-By` and no
`Claude-Session` trailer in any commit message in this repository.**

`NOTICE` carries three roles: **Sudo Apt Holdings LLC** owns the IP, **Script Kitty** built it,
**Ayla Croft** authored it (ORCID `0009-0008-9457-2160`). Written from the owner's text.
**Ultraviolet's NOTICE is deliberately not copied** — see the difference recorded in
`FINDINGS.md`.

## Gates for this tree

`mix compile --warnings-as-errors`, `mix format --check-formatted`, `mix test`, `mix credo`
if configured. No ratchet baselines: this tree starts clean and stays at zero.

## Out of scope

Publishing. Revision negotiation and `server/discover` — the next slice, in this package.
The Ultraviolet path-dep change is a separate PR in that tree with its own review.
