<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# HANDOFF — beam_mcp, after release 0.4.0; slice 016 (reachability) opens

Tag and publish are owner steps — never `mix hex.publish`, never push a tag, never bump the
version in `mix.exs`. Those were done for 0.4.0 by the owner on 2026-09-14.

The slice records — plans, findings, lane reports, signoffs, archived gate runs — live in the
project's internal tree, not in this repository. Nothing here summarises a review that has not
happened.

## State

- **`0.4.0` is released**: tag `v0.4.0`, published on Hex on 2026-09-14, `main` at the release
  commit. Its changelog section is dated and is not amended. It carries everything since
  `0.3.1`: the catalog-contract break (`BeamMCP.ToolCatalog` replaced by `BeamMCP.Catalog`) and
  the connectome — declared, observed, canonical bytes, diff — with the Livebook, the
  benchmark, property and instruments gates, and the docs census.
- `mix.exs` says `0.4.0`. The README recommends `~> 0.4.0`, and a test binds that requirement
  to the version and refuses `0.3.1` across the catalog break.
- **No head hash is written here** — a hash written into the file it describes cannot include
  the commit that writes it. `git log main..slice/016-reachability` is the authority.
- Gate on `main` at the release: thirteen steps, every line `pass` — format (the tracked set,
  not a glob), compile, instruments, test, credo, properties (6 at 1 000 generations), optional
  deps, bench (the collector's overhead under the 1.5 µs ceiling; the diff engine's cost
  recorded, no threshold by the owner's decision), docs, reuse, licence files, publication,
  messages. **6 properties, 430 tests, 0 failures.**
- `CHANGELOG.md` has an empty `[Unreleased]` section again; the next release is `0.5.0`.

## What 016 is

Control-reachability queries over the declared graph, `BeamMCP.Connectome.Reach`: can entry E
reach effect X; can it do so on a path that crosses no gate node (with the witness path when
it can); does G dominate X from the entry set; the set of nodes every path to X must cross.
On OTP's `:digraph`/`:digraph_utils`, with dominators hand-written (`:digraph_utils` has none —
measured), and **no new dependency** — the owner declined `libgraph`; zero dependencies is part
of what the package sells. Path-explosion caps are named parameters with defaults; a query over
a cap is refused with a named error; all-paths enumeration and motif isomorphism are refused by
name, not attempted. Red first: the gate fixture, the bypass fixture, the witness-path property,
the cap refusal.

## Owner decisions still open, carried from 015

1. **The diff engine's cost is recorded, not gated** (owner, 2026-09-14): a one-shot with a
   ~35 % run-to-run spread on one machine; revisit when 016 or 017 lands and graph cost becomes
   something a consumer feels, with a warm-up-and-median benchmark built like
   `bench/overhead.exs`.
2. **The Livebook is not opened from hexdocs.** ExDoc would copy it with a badge, but a copy
   fetched by URL has no `exports/` beside it; it is run from a checkout and linked from the
   README. Whether Livebook fetches attached files on a URL import is unmeasured.
3. **The generation count** of the properties step (1 000) and the format population's form
   are the agent's; both are one line in `tools/gate.sh`.

## Known limits, recorded rather than fixed

- An Elixir script under `tools/` is parsed by the format step and run by nobody; a call into
  a module the package renamed is caught only when the script is next run by hand. The shell
  and Python instruments are parsed, not run.
- The collector is node-wide: every dispatch on the node lands in its table, whatever the
  server. The Livebook's observed export is restricted to its server by id for that reason.
- `readme_claims_test.exs` pins the claims listed in it and derives no claim set; the docs
  census closes a neighbouring gap (names that do not exist, and short aliases ExDoc would not
  link), not that one.
- The 1.5 µs ceiling's margin on this machine: the worst measured since it was set is
  +0.878 µs/call, with the baseline alone swinging 1.4 µs between runs; the owner read the
  numbers and kept the ceiling. `bench/overhead.exs` says so beside the constant.

## To release 0.5.0, when 016 and 017 have landed

1. Merge the slice PRs to `main` by rebase (the ruleset requires two green checks).
2. The release commit — `mix.exs`, the README requirement, the `[0.5.0]` heading's date,
   `SECURITY.md`'s table, this file — is the owner's; the agent prepares it as a patch measured
   on a preview and stops.
3. `mix hex.publish`, then tag `v0.5.0` signed — or tag first and publish immediately after.
   The GitHub ruleset targets **branches, not tags**, so a tag push is unprotected: what is
   tagged is what was read.
