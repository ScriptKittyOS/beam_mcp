<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# API stability

What a consumer who pinned `beam_mcp` with `~>` and reads the CHANGELOG can rely on, stated
once, and held by a test. This page is the policy; `docs/public-api.txt` is the surface it
applies to, one line per entry; `test/beam_mcp/public_api_census_test.exs` is what
fails when the surface moves without the record this page requires.

## What is public

**Public is what ex_doc lists.** Every function, macro, callback and type in a module whose
`@moduledoc` is present is public unless its `@doc` is `false`. A missing `@doc` is still listed
and still public. Hiding is explicit (`@doc false`, `@moduledoc false`), with one Elixir
convention to know: `@impl true` marks a callback implementation `@doc false` unless `@doc` is
set, so a behaviour's callbacks implemented here are off the list. That is why the HTTP
transport's `init` and `call` (the two `Plug` callbacks a host's pipeline reaches, hidden by
their `@impl Plug`) are not entries: the transport being a `Plug` is promised by its module
documentation and by the README, not by this list. A module with `@moduledoc false` is private surface: callable,
since the BEAM hides nothing, but unpromised: it can change or go in any release with no
entry. Today no module under `lib/` is private (every one of the 26 carries a `@moduledoc`),
and `docs/public-api.txt` lists their 128 public entries as of this page's writing, 25 of them
with a default argument.

The baseline is a tracked file in the package, written by a command from the compiled
application's documentation chunks and never by hand:

    MIX_ENV=test mix run -e "BeamMCP.PublicAPI.write_baseline!()"

It keeps every marker in place, adds a line for what the application has gained, and marks
what it has deprecated or lost; it never deletes a line. Its grammar is one line per entry,
`Module kind name/arity`, then `defaults=N` when the function has `N` default arguments
(`run(opts \\ [])` is `run/1 defaults=1`, callable as `run/0` as well, so dropping a default
removes a callable arity and is a change to the entry), then markers:

| marker | meaning |
| --- | --- |
| `since=R` | first shipped in release `R` |
| `deprecated_since=R` | `@deprecated` first shipped in release `R` |
| `removed_in=R` | left the public surface in release `R`: a deletion, a rename, an arity or defaults change, or a `@doc false` |

`R` is a release number, or the word `Unreleased` while the change waits in the CHANGELOG's
Unreleased section; the release that ships it writes its number in
(`MIX_ENV=test mix run -e 'BeamMCP.PublicAPI.release_markers!("0.10.0")'`, one step of cutting
a release), and the census refuses a leftover `Unreleased` once that section is empty. That
step is the one place that knows the release's number, so it holds the three rules the census
cannot: with a `removed_in=Unreleased` line in the file it refuses a patch number, and on
`1.x` any number that is not a major. A line
changes state; it is not deleted, with one exception: an entry that comes back after a
removal, whose `removed_in` is deleted and `since` set again. The tree carries what left and
when, and the census reads the tree, never git history. Two hand edits are invisible to a
tree-only census, the same as editing any pinned list: a line deleted outright, and a removal
marked with the last release's number instead of `Unreleased` (the census reads a released
number as a past cycle's record). Both are a reviewer's line (a `-` line in the diff of
`docs/public-api.txt`, or a `removed_in` that is not `Unreleased` arriving in a change) and
not this page's promise.

**Promised separately, by their own pages, not by this list:** the wire: which protocol
revisions the transports serve and what each request is answered with (`README.md`); the
exported bytes: the canonical envelope's `schema_version` and its `algorithm`, whose history
and verifier consequences are in `docs/connectome-canonical.md` and `docs/connectome-diff.md`;
the host contract: the `BeamMCP.Catalog` behaviour, whose callbacks are entries here, the
`Plug` contract of `BeamMCP.Transport.HTTP`, and the options the transports and the tracer
take, documented on their modules and functions; the `:telemetry` events, their measurements
and metadata (`docs/connectome-observed.md`); and the tracer's exit reasons, documented on
`BeamMCP.Connectome.Tracer`. **Promised by the typespecs, not by this list's names:** the
fields of the public structs and the shapes behind the `@type`s and `@spec`s. A field renamed
or a return shape changed leaves `Module kind name/arity` untouched, so the census does not see
it; such a change is a break like any other and is a reviewer's line and a CHANGELOG entry,
not a census failure, unless it is growth that *What may grow, and how*, below, allows. **Not promised anywhere:** the shape of `inspect/1` output, the text of
log lines and error messages, the names of the tracer's processes and trace session, and the
layout of the observed collector's ETS rows beyond the `row/0` type
`BeamMCP.Connectome.Observed` documents.

## Versioning

**While the package is `0.x`, breaks land at the minor position** and are documented as such.
From the release this page ships in, a break is a CHANGELOG heading carrying the word
**BREAKING** whose section carries a **"How to tell whether you are affected"** sentence (the
census holds the Unreleased section to that), and `UPGRADING.md` lists them. Earlier releases
documented their breaks under headings of their own wording (`0.2.0`'s "two fields are
REMOVED", `0.4.0`'s "BREAKING, and it breaks a host contract"); `UPGRADING.md` names each with
its CHANGELOG heading. That is why the README recommends the current minor at three numbers (`~> 0.10.0`) rather than two (`~> 0.10`): the
tighter pin stops at the next minor, which is where the next documented break can be. A patch
release carries no break to the public surface, the wire, the exported bytes or the host
contract, a rule the census cannot check (it does not know which number the next release
will carry) and the release step can: `release_markers!/1` refuses a patch number while a
removal waits.

**From `1.0.0`, the package follows semantic versioning:** the public surface listed in
`docs/public-api.txt` at `1.0.0` changes incompatibly only in a major release; a minor adds
and deprecates; a patch fixes. `1.0.0` follows once the public API and the stated threat model
have each survived a full minor release unchanged (the README's condition, and the only one
stated); `UPGRADING.md` carries what a `0.x` consumer must do to reach it.

## What may grow, and how

1.0.0 freezes this package's own call surface. It does not freeze a value set that the
protocol, a shared contract (the canonical bytes, the signature schemes, the digest names) or a
system built beside this one may still extend. Five rules say how each kind of thing grows.

**Value sets: open by default.** Every named type, and every public struct field, whose
definition is a union of atoms is listed below, OPEN or CLOSED. An OPEN set may gain a value at a minor release: code that matches on it keeps
a catch-all clause, and a value it does not know is not an error. A CLOSED set changes only at
a major. Every value set not in the table, an atom nested in a list, a tuple or an error reason
included, is OPEN. Every error reason a function returns is OPEN in particular, and
`BeamMCP.JSON.decode/1` promises the two reasons it names (`{:nesting, depth, max}`,
`{:duplicate_key, key}`) and nothing about any other: which decoder produced it, and in which
shape, is unspecified. The table is held by `test/beam_mcp/growth_table_test.exs` "every atom
union in a public type has exactly one row, with its atoms and OPEN or CLOSED", which reads the
compiled types, so a union that grows, shrinks or appears without its row fails.

| Type | Values | Growth |
| -- | -- | -- |
| `t:BeamMCP.Connectome.Node.kind/0` | `:server` `:tool` `:resource` `:resource_template` `:prompt` `:process` `:module` | OPEN |
| `t:BeamMCP.Connectome.Node.level/0` | `:mfa` `:module` `:boundary` `:server` | OPEN |
| `t:BeamMCP.Connectome.Edge.kind/0` | `:invoke` `:read` `:message` `:supervise` | OPEN |
| `t:BeamMCP.Connectome.Edge.provenance/0` | `:declared` `:observed` | OPEN |
| `t:BeamMCP.Connectome.Edge.sign/0` | `:allow` `:deny` `:hold` `:ungoverned` `:unset` | OPEN |
| `t:BeamMCP.Connectome.Canonical.algorithm/0` | `:sha256` `:sha384` `:sha512` | OPEN |
| `t:BeamMCP.Connectome.Canonical.scheme/0` | `:ed25519` `:ecdsa_p384_sha384` `:mldsa87` | OPEN |
| `t:BeamMCP.ToolSpec.t/0` field `mode` | `:read_only` `:proposal` | OPEN |

None is CLOSED today. A set is CLOSED only when it is this package's alone and a consumer's
exhaustive match on it is the point; the column exists so that such a set can say so.

**Encodings: versioned, not frozen.** An encoding a shared contract governs carries its
`schema_version` inside the bytes. It changes only as a new version at a minor, and bytes at an
older version are never rewritten and keep verifying by their own version's rule. The canonical
connectome bytes are the first: `4` since the node vocabulary gained `resource_template`, with
the bytes `0.6.0` to `0.10.1` wrote at `3` kept as goldens and verified under the code that
writes `4` (`test/beam_mcp/connectome/canonical_test.exs` "versioned, not frozen: bytes at 3
still verify under the code that writes 4"; `docs/connectome-canonical.md`, *Versions*). In
`0.x` such a version is a documented break, like every break. From `1.0.0` it is the one change
a minor may make to bytes a consumer pins: the alternative is freezing a contract other systems
share. It ships with a CHANGELOG heading naming the new version and a "how to tell" sentence;
the old version's bytes keep verifying; and code that builds the structure passes the version
the package exports (`BeamMCP.Connectome.Graph.schema_version/0`), never a literal, which a
new version refuses.

**Request context: one reserved key.** What a request carries beyond its arguments reaches the
host's dispatch under the `:mcp` key of its third argument (the request's `params._meta`, the
client's capabilities, the revision served; `BeamMCP.Server` `t:dispatch/0`). A later field,
the next protocol addition that rides in `_meta`, joins that map at a minor, never as a new
function or a new argument; a host matches the keys it reads.

**Wire bytes: stable in 1.x.** Every JSON value the transports write has its object keys in
sorted order at every depth (a struct is written by its own `Jason.Encoder`), and a refusal
walks a client's arguments in sorted order too, so a response's bytes are a function of its
content and not of the OTP release's map iteration order (`test/beam_mcp/wire_bytes_test.exs` pins one sha256 per
response on every CI leg). Field values are the protocol's; a field the protocol adds is an
addition to the bytes, not a break.

**Behaviours: callbacks are added optional.** A callback joins `BeamMCP.Catalog` or
`BeamMCP.Server` at a minor only under `@optional_callbacks`, never as required: a module
written against the earlier behaviour keeps compiling without a warning. `BeamMCP.Signer` is the
one exception by design: its single callback is a boundary (will-not-implement entry 3), held
exactly by `test/beam_mcp/boundary/no_signature_test.exs`, and it does not grow.

## Deprecation: three steps, three minors

A public entry that is going to leave goes in three steps, each on the record:

1. **`@deprecated`, with the replacement already shipped.** The function carries
   `@deprecated "use ..."` (the compiler warns every caller at their compile), the writer
   marks its baseline line `deprecated_since=Unreleased`, and the CHANGELOG's Unreleased
   section names the exact `Module.name/arity` in a bullet that records the deprecation and
   its replacement. The replacement exists in the same release or an earlier one; a
   deprecation that points at nothing is not one (a rule of review: the census checks the
   attribute, the marker and the bullet, not what the message names). Every caller of the
   entry inside the package moves to the replacement in the same change; the package
   compiles with warnings as errors, so its own call to a deprecated function is a failed
   build, which is the right answer.
2. **Three minors of warning.** Three minor releases ship with the deprecation before the
   release that removes the entry: deprecated in `0.6.0`, it may be removed once `mix.exs`
   (the latest release) reads `0.8.0`, so `0.6`, `0.7` and `0.8` shipped with the warning and
   the removal ships in `0.9.0`. An entry deprecated on `0.x` and still present at `1.0.0` is
   on the `1.0.0` surface and waits like any `1.x` entry: three minors of the new major
   (`mix.exs` at `1.3.0`). The same count holds on `1.x`, where the release that carries the
   removal is a major: the census cannot check that number, and the release step does:
   `release_markers!/1` refuses a `1.x` minor while a removal waits.
3. **Removal, on the record.** The writer marks the line `removed_in=Unreleased`, and the
   CHANGELOG names the entry again, in the release that removes it.

**A `0.x` break may skip the wait, said in so many words.** While the package is `0.x` an
entry may be removed, renamed or have its arity or defaults changed without three minors of
`@deprecated` if the CHANGELOG bullet that names it says it is a **documented break at the
minor** (the README's rule for `0.x`, "documents breaks at the minor position", in a fixed
form) under a **BREAKING** heading whose section
carries the "How to tell whether you are affected" sentence. A first-time `@deprecated` in the
same change as the deletion does not count as the wait. From `1.0.0` there is no such skip:
the census reads `mix.exs`'s major, so the sentence stops counting the moment `1.0.0` has
shipped (the cycle that cuts `1.0.0` itself still reads `0.x` and may use it, as SemVer
allows before the first stable release).

**A docs-hidden flip is a removal.** `@doc false` on a public entry, or `@moduledoc false` on
a public module, takes it off the surface a consumer can rely on, and is treated exactly as a
deletion: `removed_in` on the line, the CHANGELOG naming it, and the same wait or the same
`0.x` sentence. There is no silent hide.

**How this compares.** Elixir itself deprecates in three steps: a soft deprecation in the
CHANGELOG and docs, then warnings once the alternative "MUST exist for AT LEAST THREE minor
versions", then removal "only … on major releases" (its "Compatibility and deprecations"
page); Phoenix, Ecto and Plug record deprecations in CHANGELOG sections of their own. This
package takes the three steps and the three-minor count, and places the count between the
warning and the removal rather than between the replacement and the warning; it adds what
none of the four does, a pinned list and a test; and it has a `0.x` regime, which those
projects, all past `1.0`, do not need.

## The census, exactly

The census compares the compiled application's documentation chunks with
`docs/public-api.txt` and both with the CHANGELOG's Unreleased section. A documented public
entry may change only if **all** of the following hold in the same change:

1. The baseline moves with it: a new line for an addition, a marker for a deprecation or a
   removal (the writer does both).
2. The CHANGELOG's Unreleased section names the exact `Module.name/arity`, the arity ending
   there (a type or callback may carry its `t:`/`c:` prefix). Not the name alone; not the
   module alone.
3. The kind-specific condition:
   - **still present, leaving later:** `@deprecated` on the entry and `deprecated_since` on
     its line, and the bullet that names it records a deprecation;
   - **removed, renamed, or arity or defaults changed:** `removed_in` on its line, and either
     `deprecated_since` naming a release with three minors shipped since (step 2's count),
     or (on `0.x` only) the bullet says *documented break at the minor* under a BREAKING
     heading with the how-to-tell sentence;
   - **docs-hidden:** as a removal.

Each kind has its one condition set; there is no OR between them. This cycle's markers are
the `Unreleased` ones, held to the Unreleased section; the release writes its number in, and
the census refuses an `Unreleased` marker beside an empty Unreleased section.

What the census showed red before it was trusted, each with the baseline unchanged unless
said: a public function deleted; renamed; hidden with `@doc false`; a default argument
dropped; removed with the baseline moved and the CHANGELOG silent; the same with a sibling
deprecated instead; removed with the CHANGELOG naming it but the `@deprecated` first added in
the same change; removed and named with the `0.x` sentence but no BREAKING heading, or no
how-to-tell sentence; removed and named on a `1.x` tree with two minors of deprecation, or
with the `0.x` sentence; `@deprecated` with no marker; with the marker and no bullet; the
marker with no `@deprecated`. And green: removed with the CHANGELOG naming it and three
minors of `deprecated_since` on the tree; removed with the `0.x` sentence under a BREAKING
heading with the how-to-tell sentence; deprecated with the attribute, the marker and the
bullet.
