<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# HANDOFF — beam_mcp, release 0.5.0 prepared; the release commit is the owner's

Tag and publish are owner steps — never `mix hex.publish`, never push a tag, never bump the
version in `mix.exs`. Those were done for 0.4.0 by the owner on 2026-09-14 and are done the
same way for 0.5.0.

The slice records — plans, findings, lane reports, signoffs, archived gate runs — live in the
project's internal tree, not in this repository. Nothing here summarises a review that has not
happened.

## State

- **Everything since `0.4.0` is in `[Unreleased]`**, with a paragraph under the heading saying
  what moved on the wire and citing the recording that holds the connectome surface to having
  moved nothing. Eight slices landed by rebase: reachability (`BeamMCP.Connectome.Reach`), the
  conformance harness and the four wire fixes it forced (one a break: `params._meta`), the
  will-not-implement page with its censuses, the sign vocabulary (a break in the bytes), the
  pages in the tarball, the resources primitive and the cursor, the prompts primitive, and the
  connectome on the wire (`BeamMCP.Connectome.Surface`). Four breaks — one on the wire, one in
  the exported bytes, two in the host contract — each with a how-to-tell sentence in its entry.
- `mix.exs` still says `0.4.0`; the README still recommends `~> 0.4.0`. The release commit —
  `mix.exs`, the README requirement and its paragraph (a fourth use of the minor position),
  the `[0.5.0]` heading's date, `SECURITY.md`'s table, the wire recording re-taken at the new
  version (it pins the version the results carry, and says so), this file's title — is
  prepared as a patch measured on a preview and applied by the owner.
- **No head hash is written here** — a hash written into the file it describes cannot include
  the commit that writes it. `git log main..slice/018-release-0-5-0` is the authority.
- Gate on the slice head: thirteen steps, every line `pass` — format (the tracked set, not a
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

## To release 0.5.0

1. Merge the slice PR to `main` by rebase (the ruleset requires two green checks).
2. Apply the release patch — or say the word and the agent applies it — then the gate on the
   result, thirteen `pass`, output recorded by command and exit code.
3. `mix hex.publish`, then tag `v0.5.0` signed — or tag first and publish immediately after.
   The GitHub ruleset targets **branches, not tags**, so a tag push is unprotected: what is
   tagged is what was read.
