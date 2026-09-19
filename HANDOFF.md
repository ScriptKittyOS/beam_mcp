<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# HANDOFF — beam_mcp, release 0.7.0 prepared; publish and tag are the owner's

Tag and publish are owner steps — never `mix hex.publish`, never push a tag, never bump the
version in `mix.exs`. For 0.7.0 the version bump is this release commit, reviewed like any
other change; publishing and tagging remain the owner's, in the order the runbook below gives.

The slice records — plans, findings, lane reports, signoffs, archived gate runs — live in the
project's internal tree, not in this repository. Nothing here summarises a review that has not
happened.

## State

- **`0.7.0` carries the signer seam and nothing else**: `BeamMCP.Signer` (one callback,
  `sign/2`, two arguments with pinned names), `BeamMCP.Signer.None` (the one no-op under
  `lib/`) and `BeamMCP.Connectome.Canonical.signature/3` (the one call site, over `encode/2`'s
  bytes, moving no envelope byte). Three public entries added, none removed, renamed or
  hidden; `docs/public-api.txt` marks them `since=0.7.0` (the release step wrote three). The
  no-signature census pins the seam — the callback's whole spec, each behaviour's exact
  callback list, the one `def sign`, the one call site — and sixteen mutants hold it. The
  signer that holds a key, `BeamMCP.Signer.Ed25519` (Ed25519 through OTP's `:crypto`, the key
  under `opts[:private_key]`), is the separate package `beam_mcp_signer`
  (github.com/ScriptKittyOS/beam_mcp_signer, unpublished until this release is on hex.pm);
  this package does not depend on it. `mix.exs` says `0.7.0`; the README recommends
  `~> 0.7.0` and the requirement test refuses `0.6.0` and `0.5.0`; the wire recording's ten
  version lines are re-taken.
- **`0.6.0` carried everything since `0.5.0`**: the wire hardening after the threat model, the
  threat-model page, the hash-agile canonical envelope (the release's one break), the install-floor slices (the OTP floor at
  compile time, the CI matrix on three pairs, the dependency audit, build provenance, the
  security policy, the instruments and Dialyzer, the tracer in its own trace session, the
  API-stability policy with `docs/public-api.txt` pinned by a census) and, after them,
  governance and succession, the export-control statement and REUSE compliance by the
  specification's tool. **One break at the minor**, in the exported bytes (the canonical
  envelope's algorithm member and `schema_version` 3), with its how-to-tell sentence. **The
  road from here is written in `UPGRADING.md`** — `0.7.0` the signer seam, `0.8.0` a quiet
  minor, `1.0.0` after it — so nobody reads it off a plan's label.
- At `0.6.0` the README recommended `~> 0.6.0` (a fifth use of the minor position) and
  `docs/public-api.txt` carried no `Unreleased` marker, so `release_markers!("0.6.0")` wrote
  nothing; at `0.7.0` it wrote three.
- **No head hash is written here** — a hash written into the file it describes cannot include
  the commit that writes it. `git log v0.6.0..main` is the authority.
- Gate on the release commit: fifteen steps, every line `pass` (the 0.5.0 gate had thirteen;
  the audit step made it fourteen in 024 and Dialyzer fifteen in 027a) — format (the tracked set, not a
  glob), compile, instruments, test, credo, properties (11 at 1 000 generations), optional
  deps, bench (the collector's overhead under the 1.5 µs ceiling; **the diff engine's run and
  encode each under its own ceiling now** — 245 ms and 260 ms, medians of five in a fresh
  process after a warm-up, set at roughly double the stable worst of ten runs on the release
  head; the reachability queries' cost recorded and judged by no number, but a query refused
  on the fixture fails the step by name), docs, reuse, licence files, publication, messages.
  **11 properties, 705 tests, 0 failures** on the release tree (692 at 0.6.0, 604 at 0.5.0;
  the differences are the slices' own pins — at 0.7.0 the signer seam's census and behaviour
  tests; before it the floor, the provenance and security-policy pins, the tracer's session
  suite, the public-API census on the tree and on fixtures, the governance and export-control
  censuses).
- The README's four-way split is held by census to the modules compiled from `lib/` (the
  beams whose source is under `lib/`, not the test build's `.app`, which also lists
  `test/support`): every module named under *shipping now* is among them, every module named
  under the other three paragraphs is not.

## What is next

The road, as `UPGRADING.md` states it and the owner locked it: **`0.7.0`** this release, the
signer seam (`BeamMCP.Signer`, a behaviour added to the public surface and no authority — the
last intentional addition), **`0.8.0`** a quiet minor in which no public entry moves,
**`1.0.0`** after it has stood — the README's condition, that
the public API and the stated threat model have each survived a full minor release unchanged.
The federation seam stays held on another board's answer and is not on that road. A compiler-tracer census
(module-body code run at compile time, which neither the text censuses nor `:xref` see) is
scheduled with its lift measured. Sign-aware reachability, if asked for, is a later slice or a
refusal decided in the open — never a widening inside a release slice; `all_paths` stays
refused.

## Owner decisions still open

1. **Subscriptions.** `resources/subscribe` is not in `2026-07-28` (`subscriptions/listen`
   replaced it, a long-lived stream the stateless HTTP transport cannot hold); the capability
   is advertised with `subscribe: false`. Whether to build `subscriptions/listen` on stdio, the
   legacy pair on the legacy era only, or neither and say so on the will-not-implement page.
2. **A resource template in the declared connectome.** The builder reads a `uri` per entry; a
   template has a `uri_template` and is enumerated as unreadable — true and unflattering.
   Whether a template is a node, and of what kind.
3. **`tools/list` pagination.** The cursor exists and both resource lists and `prompts/list`
   use it; adopting it on `tools/list` changes an existing result and waits for the word.
4. **The diff encode's cost follows the caller's heap.** Measured while rebuilding the
   benchmark: 115–126 ms in a fresh process, 133–151 ms after one encode in the same process,
   240–252 ms in a process holding six earlier records. The gate's figure is the fresh one and
   says so; whether a long-lived caller should encode in a spawned process is unmeasured on a
   real host.
5. **The Livebook is not opened from hexdocs**, as before: a copy fetched by URL has no
   `exports/` beside it.

## Known limits, recorded rather than fixed

- An Elixir script under `tools/` is parsed by the format step and run by nobody; a call into
  a module the package renamed is caught only when the script is next run by hand.
- The censuses that read the built beams (`BeamMCP.Boundary.lib_modules/0`: the split census,
  the package-reach census) read what the last compile left in the ebin; a beam outside Mix's
  manifest whose source says `lib/` is counted until it is deleted. Not measured; stated on the
  function.
- The collector is node-wide: every dispatch on the node lands in its table, whatever the
  server. The Livebook's observed export is restricted to its server by id for that reason.
- `readme_claims_test.exs` pins the claims listed in it and derives no claim set; the docs
  census closes a neighbouring gap (names that do not exist), and the split census another
  (a module named in the wrong paragraph), not that one.
- The 1.5 µs ceiling's margin on this machine: the worst measured since it was set is
  +0.878 µs/call, with the baseline alone swinging 1.4 µs between runs; the owner read the
  numbers and kept the ceiling. `bench/overhead.exs` says so beside the constant.
- The `2025-11-25` revision is served on stdio only; over HTTP the conformance row for it is
  0 / 30 by design, and the README says so beside the number.

## The release steps — the runbook (followed for 0.6.0; the same for 0.7.0)

1. The release PR merged to `main` by rebase (the ruleset requires two green checks); `main`
   is then the release commit.
2. The gate on that commit, fifteen `pass`, output recorded by command and exit code (the
   release PR's own gate run is that record).
3. Tag the release commit **as it sits on `main` after the rebase-merge** (a new SHA; the
   bytes are a function of the tree, measured) locally, signed (`git tag -s vX.Y.Z`); then
   `tools/release_tarball.sh vX.Y.Z beam_mcp-X.Y.Z.tar --publish` (the script builds the
   canonical tarball from `git archive` of that tag and publishes from that tree — a
   working-tree `mix hex.publish` ships that machine's file modes and is not what the
   provenance workflow attests); **then** push the tag. The tag's run downloads what hex.pm
   serves and verifies the attestation against it, and treats a version hex.pm does not serve
   yet as a failure — so the push comes last. (A tag and its commit build the same bytes;
   measured.) The GitHub ruleset targets **branches, not tags**, so a tag push is
   unprotected: what is tagged is what was read.
