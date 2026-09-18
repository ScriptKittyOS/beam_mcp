<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# HANDOFF — beam_mcp, after release 0.5.0

Tag and publish are owner steps — never `mix hex.publish`, never push a tag, never bump the
version in `mix.exs`. Those were done for 0.5.0 by the owner, as for 0.4.0.

The slice records — plans, findings, lane reports, signoffs, archived gate runs — live in the
project's internal tree, not in this repository. Nothing here summarises a review that has not
happened.

## State

- **`0.5.0` carries everything since `0.4.0`**, with a paragraph under its heading saying
  what moved on the wire and citing the recording that holds the connectome surface to having
  moved nothing. Eight slices landed by rebase: reachability (`BeamMCP.Connectome.Reach`), the
  conformance harness and the four wire fixes it forced (one a break: `params._meta`), the
  will-not-implement page with its censuses, the sign vocabulary (a break in the bytes), the
  pages in the tarball, the resources primitive and the cursor, the prompts primitive, and the
  connectome on the wire (`BeamMCP.Connectome.Surface`). Four breaks — one on the wire, one in
  the exported bytes, two in the host contract — each with a how-to-tell sentence in its entry.
- `mix.exs` says `0.5.0`. The README recommends `~> 0.5.0` (a fourth use of the minor
  position, the paragraph beside it naming the three kinds of break), and a test binds that
  requirement to the version and refuses `0.4.0` across them. The wire recording was re-taken
  at this version, since it pins the version the results carry; the fixture catalog without
  the surface's entries is still what "before" means.
- **No head hash is written here** — a hash written into the file it describes cannot include
  the commit that writes it. `git log main..slice/018-release-0-5-0` is the authority.
- Gate on the release commit: thirteen steps (the audit step made it fourteen in 024 and Dialyzer fifteen in 027a, after
  this release), every line `pass` — format (the tracked set, not a
  glob), compile, instruments, test, credo, properties (11 at 1 000 generations), optional
  deps, bench (the collector's overhead under the 1.5 µs ceiling; **the diff engine's run and
  encode each under its own ceiling now** — 245 ms and 260 ms, medians of five in a fresh
  process after a warm-up, set at roughly double the stable worst of ten runs on the release
  head; the reachability queries' cost recorded and judged by no number, but a query refused
  on the fixture fails the step by name), docs, reuse, licence files, publication, messages.
  **11 properties, 604 tests, 0 failures**: 599 at the head 018 opened on, plus the three of
  the README split census and the two that hold the will-not-implement page's row count to
  the README's spelled count and to the page's own placement sentence.
- The README's four-way split is held by census to the modules compiled from `lib/` (the
  beams whose source is under `lib/`, not the test build's `.app`, which also lists
  `test/support`): every module named under *shipping now* is among them, every module named
  under the other three paragraphs is not.

## What is next

The plan's order after this release: the federation seam (held on an answer from another
board about who orchestrates a merge and which key registry verifies sub-graphs — nothing
touching signing or key material is built without the owner's word), effective connectivity,
then assessability and deployability toward `1.0.0`, which follows once the public API and the
stated threat model have each survived a full minor release unchanged. A compiler-tracer census
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

## The release steps — the record of 0.5.0, and the runbook for the next

1. The slice PR merged to `main` by rebase (the ruleset requires two green checks).
2. This release commit applied by the owner, then the gate on the result, every line `pass`
   (thirteen at 0.5.0; fourteen since 024; fifteen since 027a), output recorded by command and exit code.
3. (The next release's step; 0.5.0 was published from a working tree with `mix hex.publish`,
   before the script existed.) Tag the release commit locally, signed (`git tag -s vX.Y.Z`); then
   `tools/release_tarball.sh vX.Y.Z beam_mcp-X.Y.Z.tar --publish` (the script builds the
   canonical tarball from `git archive` of that tag and publishes from that tree — a
   working-tree `mix hex.publish` ships that machine's file modes and is not what the
   provenance workflow attests); **then** push the tag. The tag's run downloads what hex.pm
   serves and verifies the attestation against it, and treats a version hex.pm does not serve
   yet as a failure — so the push comes last. (A tag and its commit build the same bytes;
   measured.) The GitHub ruleset targets **branches, not tags**, so a tag push is
   unprotected: what is tagged is what was read.
