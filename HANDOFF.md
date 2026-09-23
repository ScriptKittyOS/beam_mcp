<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# HANDOFF: beam_mcp, release 0.10.1 prepared (a security patch); publish and tag are the owner's

Tag and publish are owner steps: never `mix hex.publish`, never push a tag, never bump the
version in `mix.exs`. For 0.10.1 the version bump is this release commit, reviewed like any
other change; publishing and tagging remain the owner's, in the order the runbook below gives.

The slice records (plans, findings, lane reports, signoffs, archived gate runs) live in the
project's internal tree, not in this repository. Nothing here summarises a review that has not
happened.

## State

- **`0.10.1` is a security patch on `0.10.0`**: the project's own security review (three
  independent lanes, every finding reproduced first) found JSON booleans and `null` reaching
  dispatch as strings, the advertised schema enforced at the top level only, stdio fault
  reports on standard output, host terms in client-facing `-32603` messages, raw stacktraces
  in the HTTP transport's logs, the cursor outside the JSON reader, and non-string `method` or
  tool `name` raising in the core. Each is fixed with a test seen failing on `0.10.0` first
  (`test/beam_mcp/arguments_schema_and_faults_test.exs`); the pages that claimed more than the
  code are corrected. No public entry moved; two behaviours change (booleans preserved, an
  unsupported schema keyword refused at startup), each in the CHANGELOG with how to tell
  whether a host is affected. Handled privately under `SECURITY.md`: the advisories are
  published after the release. `beam_mcp_signer` `0.2.1` ships beside it.
  **A patch, not `0.11.0`, by `SECURITY.md`'s own table** (Critical: "a patch release of the
  supported minor carrying only the fix"; the package bytes since `0.10.0` are the fixes and
  comments), and because the README's `~> 0.10.0` pin admits `0.10.1` on a plain
  `mix deps.update` where it would stop short of a `0.11.0`. Go's and Rust's compatibility
  promises keep the same exception for security fixes. **After publishing, retire the affected
  releases** so every `mix deps.get` names the fix:
  `mix hex.retire beam_mcp 0.10.0 security --message "Security fixes in 0.10.1; see its CHANGELOG entry"`
  (and the same for earlier supported versions the advisory lists), and
  `mix hex.retire beam_mcp_signer 0.2.0 security --message "Key could be printed; fixed in 0.2.1"`.
- **`0.10.0` is the quiet minor again**: no public entry added, removed, renamed, hidden or
  changed in arity (`docs/public-api.txt` did not move; `release_markers!("0.10.0")` wrote
  nothing), no wire or envelope byte (the recording's ten version lines re-taken and nothing
  else; every canonical golden the same blob as at `0.9.0`). Instruments: the suite in FIPS
  mode in CI (`.github/workflows/fips.yml`: OTP 28.1.1 `--enable-fips` over OpenSSL 3.5.8 with
  the 3.1.2 FIPS provider, CMVP #4985; 11 properties, 729 tests, 0 failures in FIPS mode,
  measured locally on that toolchain and in CI), and an attested CycloneDX SBOM at every
  release (`tools/sbom.sh`, the EEF's `mix_sbom` pinned by digest, outside `mix.exs`; bound to
  the tarball's digest by a second attestation that the workflow downloads back and compares).
  Pages: the OpenSSF Best Practices badge's (architecture, assurance case, roadmap, code of
  conduct, code review, security-review procedure, continuity), `docs/fips.md` measured and
  corrected (a missing provider fails at the first `:crypto` call, not at boot), the
  supply-chain row's status, README's "Scheduled" after `1.0.0`, and no em dash left outside
  `slices/`. `mix.exs` says `0.10.0`; the README recommends `~> 0.10.0` and the requirement
  test refuses `0.9.0`, `0.8.0`, `0.7.0` and `0.6.0`. `1.0.0` is next, after this minor has
  stood.
- **`0.9.0` carries two additions and no break**, and ends the stand at `0.8.0`: the `:server`
  seam (a module option on `BeamMCP.Transport.HTTP`'s Plug and `BeamMCP.Transport.Stdio.run/1`,
  default `BeamMCP.Server`, the transports reaching `new/1`, `handle_message/2` and (stdio)
  `shutdown?/1` through it and never by name, `BeamMCP.Server` now the behaviour a wrapper
  implements, `shutdown?/1` optional since HTTP never asks it), and `scheme:` and `key_id:` beside
  the signature `BeamMCP.Connectome.Canonical.signature/3` returns, copied from the host's
  options and verified by nothing here, the canonical bytes unmoved. Four public entries added,
  each `since=0.9.0`; none removed, renamed, hidden or changed in arity; the `0.8.0` wire
  recording re-taken with its ten version lines moving and nothing else; every canonical golden
  the same blob as at `0.8.0`. Censuses: a new one (the transports never name the core: three
  readings over the whole of `lib/`), two moved (the variable-module call list, the behaviour
  list), one vocabulary section (`Scheme`). Will-not-implement entry 12 is unchanged, its two
  tests untouched: the seam carries no state and decides no authority. `mix.exs` says `0.9.0`;
  the README recommends `~> 0.9.0` and the requirement test refuses `0.8.0`, `0.7.0` and
  `0.6.0`. `0.10.0` is next, the quiet minor (a FIPS leg, the SBOM at release: instruments
  and pages, no public entry), then `1.0.0` after it has stood.
- **`0.8.0` was the quiet minor**: no public entry added, removed, renamed, hidden or changed
  in arity (`docs/public-api.txt` is `0.7.0`'s line for line, `release_markers!("0.8.0")`
  wrote nothing), and no wire or envelope byte moved. Instruments: the gate's sixteenth step
  diffs the baseline against `origin/main` (G-076); the pull-request summary waits for running
  legs on a body edit (G-079); the honesty probe's discriminator reads detailed pass lines
  (G-078); each with an offline probe. Pages: the governance table carries the Scorecard's
  measured figures with the rule behind each low one. `mix.exs` says `0.8.0`; the README
  recommends `~> 0.8.0` and the requirement test refuses `0.7.0` and `0.6.0`; the wire
  recording's ten version lines are re-taken. `1.0.0` is next, after this minor has stood.
- **`0.7.0` carried the signer seam and nothing else**: `BeamMCP.Signer` (one callback,
  `sign/2`, two arguments with pinned names), `BeamMCP.Signer.None` (the one no-op under
  `lib/`) and `BeamMCP.Connectome.Canonical.signature/3` (the one call site, over `encode/2`'s
  bytes, moving no envelope byte). Three public entries added, none removed, renamed or
  hidden; `docs/public-api.txt` marks them `since=0.7.0` (the release step wrote three). The
  no-signature census pins the seam (the callback's whole spec, each behaviour's exact
  callback list, the one `def sign`, the one call site), and sixteen mutants hold it. The
  signer that holds a key, `BeamMCP.Signer.Ed25519` (Ed25519 through OTP's `:crypto`, the key
  under `opts[:private_key]`), is the separate package `beam_mcp_signer`
  (github.com/ScriptKittyOS/beam_mcp_signer, 0.1.0 on hex.pm, depending on `~> 0.7.0`, so a
  host on it cannot take `0.8.0` until a signer release admits it; `UPGRADING.md` says so;
  and `0.1.1`, released 2026-09-19 with `~> 0.7`, is that release: it resolves beside `0.9.0`);
  this package does not depend on it.
- **`0.6.0` carried everything since `0.5.0`**: the wire hardening after the threat model, the
  threat-model page, the hash-agile canonical envelope (the release's one break), the install-floor slices (the OTP floor at
  compile time, the CI matrix on three pairs, the dependency audit, build provenance, the
  security policy, the instruments and Dialyzer, the tracer in its own trace session, the
  API-stability policy with `docs/public-api.txt` pinned by a census) and, after them,
  governance and succession, the export-control statement and REUSE compliance by the
  specification's tool. **One break at the minor**, in the exported bytes (the canonical
  envelope's algorithm member and `schema_version` 3), with its how-to-tell sentence. **The
  road from here is written in `UPGRADING.md`** (`0.7.0` the signer seam, `0.8.0` a quiet
  minor, `1.0.0` after it), so nobody reads it off a plan's label.
- At `0.6.0` the README recommended `~> 0.6.0` (a fifth use of the minor position) and
  `docs/public-api.txt` carried no `Unreleased` marker, so `release_markers!("0.6.0")` wrote
  nothing; at `0.7.0` it wrote three.
- **No head hash is written here**: a hash written into the file it describes cannot include
  the commit that writes it. `git log v0.9.0..main` is the authority.
- Gate on the release commit: sixteen steps, every line `pass` (the 0.5.0 gate had thirteen;
  the audit step made it fourteen in 024, Dialyzer fifteen in 027a, the baseline diff sixteen
  at 0.8.0): format (the tracked set, not a
  glob), compile, dialyzer, instruments, test, credo, properties (11 at 1 000 generations),
  optional deps, audit, bench (the collector's overhead under the 1.5 µs ceiling; **the diff engine's run and
  encode each under its own ceiling now**: 245 ms and 260 ms, medians of five in a fresh
  process after a warm-up, set at roughly double the stable worst of ten runs on the release
  head; the reachability queries' cost recorded and judged by no number, but a query refused
  on the fixture fails the step by name), docs, reuse, licence files, publication, baseline,
  messages.
  **11 properties, 729 tests, 0 failures** on the release tree (729 at 0.9.0 as well: 0.10.0's
  instruments are workflows, measured by their CI runs, and add no test; 705 at 0.8.0 and 0.7.0, since 0.8.0
  added no test and its instruments are probed by shell; 692 at 0.6.0, 604 at 0.5.0; the
  differences are the slices' own pins: at 0.9.0 the server seam's census and by-effect tests
  and the scheme's tests; at 0.7.0 the signer seam's census and behaviour tests; before it the floor, the provenance and security-policy pins, the tracer's session
  suite, the public-API census on the tree and on fixtures, the governance and export-control
  censuses).
- The README's four-way split is held by census to the modules compiled from `lib/` (the
  beams whose source is under `lib/`, not the test build's `.app`, which also lists
  `test/support`): every module named under *shipping now* is among them, every module named
  under the other three paragraphs is not.

## What is next

**`1.0.0`**, once this minor has stood: the README's condition, that the public API and the
stated threat model have each survived a full minor release unchanged. `0.10.0` moved no public
entry, and its one threat-model edit corrects a status (provenance and the SBOM shipped), not
what the model defends. The freeze is `docs/public-api.txt` as it stands; `docs/api-stability.md`'s
1.x rules take effect. After it, as additions at the minor: the federation seam (held on
another board's answer), effective connectivity, the Tasks extension. A compiler-tracer census
(module-body code run at compile time) is scheduled with its lift measured. Sign-aware
reachability, if asked for, is a later slice or a refusal decided in the open; `all_paths`
stays refused. Outside the package: `mix_sbom`'s reading of `tools: :optional` (the named
workaround in `tools/sbom.sh` goes when an upstream release reads it).

## Owner decisions still open

1. **Subscriptions.** `resources/subscribe` is not in `2026-07-28` (`subscriptions/listen`
   replaced it, a long-lived stream the stateless HTTP transport cannot hold); the capability
   is advertised with `subscribe: false`. Whether to build `subscriptions/listen` on stdio, the
   legacy pair on the legacy era only, or neither and say so on the will-not-implement page.
2. **A resource template in the declared connectome.** The builder reads a `uri` per entry; a
   template has a `uri_template` and is enumerated as unreadable: true and unflattering.
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

## The release steps, the runbook (followed for 0.6.0 to 0.9.0; the same for 0.10.0)

1. The release PR merged to `main` by rebase (the ruleset requires two green checks); `main`
   is then the release commit.
2. The gate on that commit, sixteen `pass`, output recorded by command and exit code (the
   release PR's own gate run is that record).
3. Tag the release commit **as it sits on `main` after the rebase-merge** (a new SHA; the
   bytes are a function of the tree, measured) locally, signed (`git tag -s vX.Y.Z`); then
   `tools/release_tarball.sh vX.Y.Z beam_mcp-X.Y.Z.tar --publish` (the script builds the
   canonical tarball from `git archive` of that tag and publishes from that tree; a
   working-tree `mix hex.publish` ships that machine's file modes and is not what the
   provenance workflow attests); **then** push the tag. The tag's run downloads what hex.pm
   serves and verifies the attestation against it, and treats a version hex.pm does not serve
   yet as a failure, so the push comes last. (A tag and its commit build the same bytes;
   measured.) The GitHub ruleset targets **branches, not tags**, so a tag push is
   unprotected: what is tagged is what was read.
