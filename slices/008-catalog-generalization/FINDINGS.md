<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Slice 008 — findings

## The three decisions, made deliberately

### (a) Migration path: a clean break, no deprecated `ToolCatalog` delegate

Two reasons, and the second is the load-bearing one.

The 0.x policy already protects consumers. The README recommends `~> 0.3.0`, which **excludes**
`0.4.0` — so no existing consumer is upgraded into this break by resolution. A host that wants it
asks for it, which is exactly what a break at minor is for.

And a delegate would create **a second reader**, which decision (b) forbids. `ToolCatalog.fetch/2`
delegating to `Catalog.fetch/2` is harmless; `ToolCatalog.all/0` living beside
`Catalog.capabilities/0` is not, because a host that implements both can make them disagree and
nothing would catch it. The compatibility shim would reintroduce the defect the contract exists
to prevent, in order to soften a break the version policy already handles.

The callback is also **renamed**, `all/0` → `capabilities/0`, and that is part of the same
decision. Keeping the name while changing the return from a list to a map compiles against every
existing host and fails at the first request with a `BadMapError` — a silent shape change, which
is the defect class this repository keeps finding. Renaming makes the break arrive at compile
time as an unimplemented callback, which is the loudest place it can arrive.

### (b) The single-lookup guarantee: preserved, and structurally stronger than before

Before this slice, `tools/list` called `catalog.all()` and `ToolCatalog.fetch/2` called
`catalog.all()` — **two call sites of the host's function**, agreeing by convention. Now there is
one reader:

    def tools(catalog), do: catalog.capabilities().tools

`server.ex:185` advertises through it; `Catalog.fetch/2` resolves through it. The host's function
is called from one place in `lib/`, so the two paths cannot be given different sources without
editing that line — which is what mutant `Mcat2` does, and it dies.

Pinned **by effect**, not by inspection: `catalog_test.exs` compares the names `tools/list`
advertises against the names `tools/call` accepts, for `OnlyHere`, a catalog whose tool
(`only_in_this_catalog`) exists in no other catalog in the suite. Slice 002's original test could
pass by coincidence because both sides could find the same tool via a shared default; this one
cannot.

### (c) `fetch/2`'s `@spec`: documented honestly, not caught — and the ledger it came from was wrong

The `@spec` says `{:ok, t} | :error`. A malformed host catalog makes it raise. That is now stated
in the moduledoc rather than caught, because catching would make a host bug indistinguishable
from "no such tool": a broken catalog would present exactly as a working catalog that does not
have that tool. That is the advertise-versus-call disagreement this behaviour exists to prevent,
reintroduced by the error handling meant to be defensive.

**PR #10's ledger says three shapes raise. Reproduced on this tree, four do** — and a fifth case
the ledger missed is worse than any of them (`logs/probe-fetch-spec.txt`):

    host spec.name is a binary, not an atom       {:RAISED, ArgumentError}
    all/0 returns a non-list map                  {:RAISED, BadMapError}
    all/0 returns nil                             {:RAISED, Protocol.UndefinedError}
    all/0 returns a bare map, not a %ToolSpec{}   {:returned, {:ok, %{name: :echo}}}
    module is not loaded / does not exist         {:RAISED, UndefinedFunctionError}
    CONTROL: a well-formed catalog                {:returned, {:ok, %BeamMCP.ToolSpec{...}}}

The fourth line is the one that matters. It does **not** raise: it returns `{:ok, %{name: :echo}}`
successfully, which violates the `@spec` **silently** and hands a struct-shaped thing that is not
a struct to dispatch. A raise is a loud wrong answer; this is a quiet one.

Both are closed the same way, and not by catching: `Catalog.validate/1` at `Server.new/1` refuses
all five at **startup**, including the bare-map case. `fetch/2` keeps its raise conditions, and
they are now unreachable for a server that started.

## The malformed-catalog refusal, demonstrated red before it passed

A test never observed failing is not evidence. The init-time refusal was removed from
`Server.new/1` and the five tests quoted their failures — `logs/red-malformed-catalog.txt`:

    1) an absent key is a malformed catalog, not an empty one
       Expected exception ArgumentError but nothing was raised
    2) :tools must be a list                     ... nothing was raised
    3) :tools entries must be %ToolSpec{}        ... nothing was raised
    4) a module that does not export capabilities/0 is refused ... nothing was raised
    5) capabilities/0 must return a map          ... nothing was raised

    13 tests, 5 failures
    TEST_EXIT=2

Restored — `logs/green-malformed-catalog.txt`: **`13 tests, 0 failures`, `TEST_EXIT=0`**.

## Mutation scores — both KILL, zero variance across passes

`logs/mutation-catalog.txt`, tree `8f47e1f80c4dc356b3d84d72eb1d468cfa461c49`, 2 passes each.
Two invocations, because the two mutants have different targets:

    TARGET=lib/beam_mcp/catalog.ex  tools/mutate.sh score Mcat1
    Mcat1 | 187 tests, 2 failures TEST_EXIT=2 | 187 tests, 2 failures TEST_EXIT=2
            failed: ... an absent key is a malformed catalog, not an empty one (BeamMCP.CatalogTest)
            failed: ... the refusal the README promises is the refusal the code performs (BeamMCP.ReadmeClaimsTest)

    TARGET=lib/beam_mcp/server.ex   tools/mutate.sh score Mcat2
    Mcat2 | 187 tests, 12 failures TEST_EXIT=2 | 187 tests, 12 failures TEST_EXIT=2
            failed: the single-lookup guarantee a name the catalog does not advertise is not callable either (BeamMCP.CatalogTest)
            ... 11 others, across HTTPTest, ToolSpecSchemaTest, ErrorPayloadTest, ServerTest, ReadmeClaimsTest

**Mcat1** drops `:prompts` from `@required_keys` — the smallest possible relaxation, one key out
of three, no message change, no behaviour change for a correct host. It is killed by the startup
refusal *and*, independently, by the README claim test: the README promises that refusal, so
weakening it makes the package stop doing what the README says.

**Mcat2** leaves `tools/list` reading the catalog and makes `tools/call` answer "which tool does
this name mean" from the request instead. That is slice 002's defect in the direction it actually
occurred. The single-lookup test kills it directly, and eleven others fall with it because
`find_tool/2`'s result is what carries the schema every later check reads.

### Mcat2's first version was a compiler kill, and that is recorded rather than tidied away

It returned `{:ok, spec}` unconditionally. Elixir's type checker narrowed `find_tool/2`'s return
to that one shape, declared the caller's `:error ->` clause unreachable, and
`--warnings-as-errors` failed the build — the score line came back with **no test count at all**:

    Mcat2 |  TEST_EXIT=1 |  TEST_EXIT=1

    warning: the following clause will never match: :error
    ... typing violation found at: lib/beam_mcp/server.ex:223
    Compilation failed due to warnings while using the --warnings-as-errors option

`CONVENTIONS.md`: a compiler kill records a kill that never happened. No test ran. The mutant was
rewritten to keep the return a union — an `:error` for the empty name only — so the suite scores
it instead of the compiler. **The mutant was corrected so it could be scored, not weakened until
it killed**; every name a client can actually send is still callable under it, which is the whole
defect intact. The failed run is left in the log above the corrected one.

## Two things found while doing this, neither predicted

**The brief's call-site list was incomplete, and checking it was not optional.** It named four
sites; the tree has five readers of the contract in `lib/`. `server.ex:313` (`new/1`'s validation)
and `http.ex:225` (`init/1`'s export check) were not on the list. In the other direction,
`server.ex:311` **is** on the list and is *not* affected — it consumes a `ToolSpec`, not the
catalog. A list of call sites that is accepted rather than derived is a claim about the tree, and
this one was wrong in both directions.

**The two init paths cannot both check the same thing, and the asymmetry is deliberate.**
`Server.new/1` calls `Catalog.validate/1`, which calls `capabilities/0` — host code, at runtime.
`Transport.HTTP.init/1` deliberately does **not**: Plug's default `init_mode` is `:compile`, so
`init/1` runs at the *host's compile time*, and a correct catalog that reads config or ETS would
crash there. So the transport checks only `function_exported?(catalog, :capabilities, 0)` — a
structural check that needs no call — and leaves the shape to `new/1`. This is one mechanism
reading one kind of input in two places with two different checks, which normally reads as the
defect `CONVENTIONS.md` names. It is not: the two places are at different *times*, and the check
that cannot run at compile time is the one omitted there. Recorded because it looks wrong until
you know why.

**Four tracked probes were still on the old contract, and `lib/` is the wrong population to
check.** Acceptance criterion 1 says "nothing in `lib/` reads `tool_catalog.ex`", and that was
true while `tools/probe_ping.exs` and the three probes in `tools/probes/` each carried three
separate breaks: `@behaviour BeamMCP.ToolCatalog`, `def all`, and `catalog: ` spelled
`tool_catalog: `. The gate cannot see them — it never compiles `tools/*.exs` — so they would have
sat broken until the next slice tried to re-run one. They are instruments, not archives, and an
instrument that no longer runs is the same defect as an archive nobody can refetch. Fixed and
**proven by running them**: `mix run tools/probe_ping.exs` serves `echo` from `tools/list`, and
each network probe prints `PROBE_DONE` at `N=1` with the same `{297, :econnreset, ..., true}`
slice 006 measured. The lesson is the population, not the four files: the grep that found this
was the one run over the whole tree, and the one that missed it was scoped to `lib/`.

## Departures from slice 007's shape, stated rather than smoothed over

- **The issue was filed at record time, not before the code.** Slice 007's PLAN opens "Written
  before the code" and this one cannot. The plan itself did precede the implementation; the
  Linear issue (SCR-294) did not, because the brief ordered every tree change first and the
  record last. What that costs is real: nothing external witnessed the acceptance criteria before
  they were met, so they are only as good as this file.
- **No review rounds**, and the PLAN says so explicitly rather than leaving the absence to be
  inferred. Single pass by instruction. The mutants and the gate stand in for the reviewer.

## The count in the commit message was wrong, and the fix is here rather than only in git

`4a2d2e9`'s message read "172 tests before, 185 after". **185 was typed, not measured** — the run
printed `187 tests, 0 failures`. `CONVENTIONS.md` forbids exactly that, so the commit was amended
before anything was pushed and it is now `8f47e1f`. Recorded here as well because the defect is
the habit, not the digit, and an amended commit leaves no trace of the original.
