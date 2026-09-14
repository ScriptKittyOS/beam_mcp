<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# HANDOFF — beam_mcp, slice 015, release 0.4.0

Tag and publish are owner steps — never `mix hex.publish`, never push a tag. **So is the
version bump**: `mix.exs` says `0.3.1` on this branch, and the commit that says `0.4.0` is
prepared as a patch for the owner to apply (below), not made here.

The slice's records — plan, findings, lane reports, signoffs, the archived gate runs named
below — live in the project's internal tree, not in this repository. Nothing here summarises a
review that has not happened: how many rounds this slice had is in that record, written as
each round closed.

## State

- Branch `slice/015-release-0-4-0`, from `main` after slice 014 merged. **No head hash is
  written here** — a hash written into the file it describes cannot include the commit that
  writes it. `git log main..slice/015-release-0-4-0` is the authority.
- Gate green on the branch head, **thirteen steps**, every line read as `pass`: format
  (56 tracked `.ex`/`.exs` — the population is now the tracked set), compile, instruments
  (10 tracked `.sh`, 130 tracked `.py` parse), test, credo, properties (5 at 1 000 generations),
  optional deps, bench (the collector's overhead under the 1.5 µs ceiling; the diff engine's
  cost recorded), docs, reuse, licence files, publication, messages. Archived per commit.
- **5 properties, 430 tests, 0 failures**, under `systemd-run --user --scope -p MemoryMax=32G`.
  Derivation: 420 + 4 properties at the branch's opening (014 merged); +1 property (the diff's
  determinism, promoted from a test); +3 (the Livebook and its exports); +1 (the docs census);
  +6 (README claims pinned). Each step is one commit and its count is in that commit's message.
- `mix hex.build` clean on the branch head (exit 0, no warning; the tarball is git-ignored and
  was removed) and again on a preview of the release commit, where it builds `beam_mcp-0.4.0`.
- Version **`0.3.1`** in `mix.exs`, unchanged. **`0.3.1` is published on Hex and tagged**; its
  changelog section is dated and not amended. Everything since — the catalog-contract break of
  slice 008 and the connectome of 009–014 — is one release, `0.4.0`, one `[Unreleased]` section
  that the release commit renames.

## What this slice produced

    the benchmark gate       bench/overhead.exs against the owner's 1.5 µs ceiling, shown red
                             at 0.1 and green at 1.5; bench/diff.exs records and judges nothing
    the property gate        PROPERTY_RUNS read by the test helper; the gate runs the
                             properties alone at a thousand generations; shown red by a probe
                             that counted its own generations, then green without it
    the diff property        the pair generator draws its node set per side, so the endpoint
                             counts are exact and a one-endpoint mutant dies on the property
                             alone; the diff's determinism is a property
    the gate's population    the format step reads git ls-files, not a glob; an instruments
                             step parses every tracked shell and Python file; three broken
                             tracked instruments passed the old gate green and are named now
    the Livebook             livebooks/connectome.livemd from the JSON export alone, with the
                             four exports held to the package's output by a test, and a
                             harness that evaluates the cells outside Livebook
    the docs census          every BeamMCP module and function the prose and the compiled
                             docs name exists at that arity; nine bare names qualified; ExDoc
                             groups by namespace
    README and CHANGELOG     the connectome section and the four-way split; six claims pinned
                             by tests that quote and exercise them; the release entries

Every feature above has its red archived before its green, and the gate's output is archived
at every commit with its exit code.

## Owner decisions still open

1. **The diff engine's cost has no threshold.** `bench/diff.exs` prints run and encode times
   on a 10 000-edge fixture every gate run and cannot fail. The measurements are on the record;
   the number is yours to set against them, or to leave unset and say so.
2. **The release commit.** Prepared as a patch in the internal record: `mix.exs` to `0.4.0`;
   the README's requirement to `~> 0.4.0` with its paragraph (three breaks at the minor
   position, the third in the host contract rather than on the wire); the test binding the
   requirement to the version, now also refusing `0.3.1` across the catalog break; the
   `[0.4.0]` heading dated; `SECURITY.md`'s table naming `0.4.x`. The gate was run on a preview
   of that commit: thirteen `pass`, `hex.build` clean. **Check the date and the table before
   applying** — both are yours.
3. **The Livebook is not opened from hexdocs.** ExDoc would copy it with a "Run in Livebook"
   badge, but a copy fetched by URL has no `exports/` beside it; it is run from a checkout and
   linked from the README. Whether Livebook fetches attached files on a URL import is
   unmeasured; the lift is recorded.
4. **The generation count** of the properties step (1 000) and the format population's form are
   the agent's; both are one line in `tools/gate.sh`.

## Known limits, recorded rather than fixed

- An Elixir script under `tools/` is parsed by the format step and run by nobody; a call into a
  module the package renamed is caught only when the script is next run by hand. The shell and
  Python instruments are parsed, not run.
- The collector is node-wide: every dispatch on the node lands in its table, whatever the
  server. The Livebook's observed export is restricted to its server by id for that reason; a
  host with two servers in one node gets one graph and splits it by id prefix.
- The Mermaid the notebook generates was read and evaluated, not rendered: nothing on the
  build machine renders Mermaid. The first rendering is in Livebook.
- `readme_claims_test.exs` still pins the claims listed in it and derives no claim set; the
  docs census closes a neighbouring gap (names that do not exist), not that one.

## To release 0.4.0

1. Apply the release patch (`git am`), check the `[0.4.0]` date and the `SECURITY.md` table,
   run `tools/gate.sh` and read thirteen `pass`.
2. Merge the PR to `main` by rebase (the ruleset requires two green checks).
3. `mix hex.publish`, then tag `v0.4.0` signed — or tag first and publish immediately after.
   The GitHub ruleset targets **branches, not tags**, so a tag push is unprotected: what is
   tagged is what was read.
