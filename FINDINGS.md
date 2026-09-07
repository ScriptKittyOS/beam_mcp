<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# beam_mcp — FINDINGS

Source: Ultraviolet `origin/main` = `778accb82759d3def30b2e1410e1aeb573f76dac`.
Nothing is committed in this repository yet. `main` had no commits at start.

## The seam is nominal — demonstrated red, in Ultraviolet, before any extraction

The owner named `normalize_tool_name/1` as the demonstration. It is one, and here it is
failing, run in a throwaway worktree at `778accb8` with `_build`/`deps` copied (§4b), the
test file removed and the worktree deleted afterwards:

    $ mix test apps/hacktui_agent/test/mcp_injection_defect_test.exs

      1) test tools/call on that same injected tool reaches dispatch
         apps/hacktui_agent/test/mcp_injection_defect_test.exs:24
         Assertion failed, no matching message after 200ms
         The process mailbox is empty.
         code: assert_receive {:dispatch, :novel_tool, _args, _opts}

    2 tests, 1 failure
    REAL_EXIT=2

Test 1 **passed**: `tools/list` advertised `novel_tool` from the injected catalog.
Test 2 **failed**: `tools/call` on that same tool never reached dispatch.

The cause, at `server.ex`:

    :56-57   tools = Enum.map(state.tool_catalog.all(), &tool_definition/1)   # honours injection
    :144-146 valid_names = Enum.map(ToolCatalog.all(), &Atom.to_string(&1.name))  # ignores it

An injected catalog is honoured when **advertising** a tool and ignored when **calling** it.
The existing suite passes only because `FakeToolCatalog`'s two tools are both present in the
real catalog, so the two lists happen to agree.

## Commit 1 cannot be behaviour-preserving. Reported, not worked around.

`normalize_tool_name/1` calls `HacktuiAgent.MCP.ToolCatalog.all()` **directly**, and
`ToolCatalog` is on the owner's stay-behind list. So the package cannot compile without
changing that line — and changing it *is* commit 2's fix. **Commits 1 and 2 collapse.**

The only alternative is to hardcode the six Ultraviolet tool names in the package so the
defect survives verbatim, which the scope forbids outright: domain data in a generic module
is the thing this extraction exists to remove.

## Two other changes commit 1 cannot avoid, declared

1. **The `new/1` defaults.** `dispatch:` defaults to `&Dispatch.safe_call/3` and
   `tool_catalog:` to `ToolCatalog` — both stay behind. They must become injected. No test
   changes: all four server tests pass `tool_catalog:`, and the three that omit `dispatch:`
   never reach a dispatch.
2. **`@server_name "hacktui-hermes"`** (`server.ex:11`) is Ultraviolet branding compiled into
   a generic package, and `server_test.exs:34` asserts it. Keeping it makes the package
   announce another product's name; changing it edits a test, which commit 1 forbids. It wants
   to be an injected option. **Flagged, not touched.**

## `stdio.ex` travels without test coverage

`mcp_stdio_framing_test.exs` cannot travel: it drives the real `bin/hacktui-mcp` binary,
computes `repo_root()` as the umbrella root, runs `mix compile` there in `setup_all`, and is
tagged `:mcp_e2e`. Making it run here needs a package-local launcher — new work, not a move.
So the transport ships with **no in-package test**. Recorded as a gap, not hidden.

## NOTICE — the difference the owner asked me to report rather than reconcile

Ultraviolet's `NOTICE` at `778accb8` reads, in full on the copyright line:

    Ultraviolet
    Copyright 2026 Ayla Croft

It names **one** role. It does not mention Sudo Apt Holdings LLC, Script Kitty, the ORCID, or
any separation of ownership from authorship — consistent with slice 14 being unstarted.
`beam_mcp`'s `NOTICE` is written from the owner's text and carries all three roles. **The two
files disagree, deliberately, and reconciling Ultraviolet's is slice 14's work, not mine.**
