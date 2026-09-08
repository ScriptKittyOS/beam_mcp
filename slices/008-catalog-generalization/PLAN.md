<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Slice 008 — generalize the catalog contract, so resources and prompts cost no second break

**Issue:** SCR-294 — filed at record time rather than before the code, which is a departure from
slice 007 and is recorded as one in FINDINGS.

**Number verified free in both places before claiming it**, the check a directory-versus-issue
collision made routine. `ls slices/` on `main`: `001`, `001b`, `002`, `003`, `004`, `006`, `007`
— no `008`. `git branch -a`: no `slice/008-*` and no `origin/slice/008-*` before this branch was
cut. (`005` has a branch and an issue but no directory; it is PR #15's, still unmerged.)

**This plan specifies no review rounds, and that is deliberate rather than an omission.** The
brief was a single pass — plan, implement, verify, commit, do not wait for review between steps.
Slices 002, 003 and 006 ran numbered rounds because a reviewer was scoring them; nobody is
scoring this one, so a round boundary here would be a heading with nothing behind it. The
mutants and the gate are what stands in for the reviewer, which is why both are acceptance
criteria below rather than nice-to-haves.

**Honest about its own order.** The decisions and criteria below were settled before the code was
written; the file is written at record time, after it, because the brief put every tree change
first and the record last. Two things in it were revised *by measurement* rather than by
preference, and both revisions are named where they occur rather than smoothed over.

## The defect

`BeamMCP.ToolCatalog` names one thing and returns one thing:

    @callback all() :: [BeamMCP.ToolSpec.t()]

MCP has three catalog-shaped concepts — tools, resources, prompts. This package serves the first.
Adding either of the others later means changing this callback's return type, which is a second
break for every host that has written one. The point of doing it now is that 0.x is where a break
is cheap and 1.0 is where it is not.

## The shape

    %{tools: [BeamMCP.ToolSpec.t()], resources: [], prompts: []}

Every key **required**, `resources` and `prompts` permitted to be empty and read by nothing. An
absent key is a malformed catalog, not an empty one: the two are different claims and only one of
them is checkable.

## Three decisions this forces, to be answered in FINDINGS

- **(a)** The migration path: clean break, or a deprecated `ToolCatalog` delegating to the new
  behaviour.
- **(b)** What happens to the single-lookup guarantee at `tool_catalog.ex:19-23` — the property
  that `tools/list` and `tools/call` cannot disagree.
- **(c)** `fetch/2`'s `@spec`, which claims `{:ok, t} | :error` and is violated by a malformed
  host catalog.

## Call sites to verify, all of them, not the ones a brief remembers

The brief named four. The list was checked against the tree instead of accepted, and it was
**incomplete** — the finding is in FINDINGS. Every reader of the contract in `lib/`:

    lib/beam_mcp/server.ex:185          tools/list advertises
    lib/beam_mcp/server.ex:304          find_tool/2, the tools/call gate
    lib/beam_mcp/server.ex:313          new/1's init-time validation
    lib/beam_mcp/transport/http.ex:225  init/1's export check
    lib/beam_mcp/transport/http.ex:836  the x-mcp-header annotation lookup

## Acceptance criteria, as measurements

1. `tool_catalog.ex` is gone and nothing in `lib/` reads it.
2. A malformed catalog is refused at `Server.new/1`, **demonstrated red first** — the refusal
   removed, the failures quoted, the refusal restored, quoted green.
3. The single-lookup guarantee is pinned **by effect**: what `tools/list` advertises compared
   against what `tools/call` accepts, for a catalog whose tool exists in no other catalog in the
   suite, so neither path can agree by coincidence.
4. `fetch/2`'s raise conditions are **reproduced on this tree**, not inherited from PR #10's
   ledger.
5. Two mutants in `tools/mutants/`, scored by `tools/mutate.sh`, both of which must **KILL**:
   one dropping a required key from the shape, one giving advertise and call different sources.
   A survivor is reported, not fixed by adjusting the mutant.
6. `./tools/gate.sh` green, all eight lines, exit 0.

## Out of scope

Serving resources or prompts. Any opinion about what belongs in them. `authorize/1`,
`authorize_body/2`, and their tests.
