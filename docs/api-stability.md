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
and still public. Hiding is explicit — `@doc false`, `@moduledoc false` — with one Elixir
convention to know: `@impl true` marks a callback implementation `@doc false` unless `@doc` is
set, so a behaviour's callbacks implemented here are off the list. That is why the HTTP
transport's `init` and `call` — the two `Plug` callbacks a host's pipeline reaches, hidden by
their `@impl Plug` — are not entries: the transport being a `Plug` is promised by its module
documentation and by the README, not by this list. A module with `@moduledoc false` is private surface — callable,
since the BEAM hides nothing, but unpromised: it can change or go in any release with no
entry. Today no module under `lib/` is private — every one of the 26 carries a `@moduledoc` —
and `docs/public-api.txt` lists their 128 public entries as of this page's writing, 25 of them
with a default argument.

The baseline is a tracked file in the package, written by a command from the compiled
application's documentation chunks and never by hand:

    MIX_ENV=test mix run -e "BeamMCP.PublicAPI.write_baseline!()"

It keeps every marker in place, adds a line for what the application has gained, and marks
what it has deprecated or lost; it never deletes a line. Its grammar is one line per entry,
`Module kind name/arity`, then `defaults=N` when the function has `N` default arguments —
`run(opts \\ [])` is `run/1 defaults=1`, callable as `run/0` as well, so dropping a default
removes a callable arity and is a change to the entry — then markers:

| marker | meaning |
| --- | --- |
| `since=R` | first shipped in release `R` |
| `deprecated_since=R` | `@deprecated` first shipped in release `R` |
| `removed_in=R` | left the public surface in release `R` — a deletion, a rename, an arity or defaults change, or a `@doc false` |

`R` is a release number, or the word `Unreleased` while the change waits in the CHANGELOG's
Unreleased section; the release that ships it writes its number in
(`MIX_ENV=test mix run -e 'BeamMCP.PublicAPI.release_markers!("0.6.0")'`, one step of cutting
a release), and the census refuses a leftover `Unreleased` once that section is empty. A line
changes state; it is not deleted — with one exception, an entry that comes back after a
removal, whose `removed_in` is deleted and `since` set again. The tree carries what left and
when, and the census reads the tree, never git history. Two hand edits are invisible to a
tree-only census, the same as editing any pinned list: a line deleted outright, and a removal
marked with the last release's number instead of `Unreleased` (the census reads a released
number as a past cycle's record). Both are a reviewer's line — a `-` line in the diff of
`docs/public-api.txt`, or a `removed_in` that is not `Unreleased` arriving in a change — and
not this page's promise.

**Promised separately, by their own pages, not by this list:** the wire — which protocol
revisions the transports serve and what each request is answered with (`README.md`); the
exported bytes — the canonical envelope's `schema_version` and its `algorithm`, whose history
and verifier consequences are in `docs/connectome-canonical.md` and `docs/connectome-diff.md`;
the host contract — the `BeamMCP.Catalog` behaviour, whose callbacks are entries here, the
`Plug` contract of `BeamMCP.Transport.HTTP`, and the options the transports and the tracer
take, documented on their modules and functions; the `:telemetry` events, their measurements
and metadata (`docs/connectome-observed.md`); and the tracer's exit reasons, documented on
`BeamMCP.Connectome.Tracer`. **Promised by the typespecs, not by this list's names:** the
fields of the public structs and the shapes behind the `@type`s and `@spec`s — a field renamed
or a return shape changed leaves `Module kind name/arity` untouched, so the census does not see
it; such a change is a break like any other and is a reviewer's line and a CHANGELOG entry,
not a census failure. **Not promised anywhere:** the shape of `inspect/1` output, the text of
log lines and error messages, the names of the tracer's processes and trace session, and the
layout of the observed collector's ETS rows beyond the `row/0` type
`BeamMCP.Connectome.Observed` documents.

## Versioning

**While the package is `0.x`, breaks land at the minor position** and are documented as such.
From the release this page ships in, a break is a CHANGELOG heading carrying the word
**BREAKING** whose section carries a **"How to tell whether you are affected"** sentence — the
census holds the Unreleased section to that — and `UPGRADING.md` lists them. Earlier releases
documented their breaks under headings of their own wording (`0.2.0`'s "two fields are
REMOVED", `0.4.0`'s "BREAKING, and it breaks a host contract"); `UPGRADING.md` names each with
its CHANGELOG heading. That is why the README recommends `~> 0.5.0` rather than `~> 0.5`: the
tighter pin stops at the next minor, which is where the next documented break can be. A patch
release carries no break to the public surface, the wire, the exported bytes or the host
contract — a rule of the release, which the census cannot check (it does not know which
number the next release will carry) and which `UPGRADING.md`'s table would expose.

**From `1.0.0`, the package follows semantic versioning:** the public surface listed in
`docs/public-api.txt` at `1.0.0` changes incompatibly only in a major release; a minor adds
and deprecates; a patch fixes. `1.0.0` follows once the public API and the stated threat model
have each survived a full minor release unchanged (the README's condition, and the only one
stated); `UPGRADING.md` carries what a `0.x` consumer must do to reach it.

## Deprecation: three steps, three minors

A public entry that is going to leave goes in three steps, each on the record:

1. **`@deprecated`, with the replacement already shipped.** The function carries
   `@deprecated "use ..."` — the compiler warns every caller at their compile — the writer
   marks its baseline line `deprecated_since=Unreleased`, and the CHANGELOG's Unreleased
   section names the exact `Module.name/arity` in a bullet that records the deprecation and
   its replacement. The replacement exists in the same release or an earlier one; a
   deprecation that points at nothing is not one (a rule of review: the census checks the
   attribute, the marker and the bullet, not what the message names). Every caller of the
   entry inside the package moves to the replacement in the same change — the package
   compiles with warnings as errors, so its own call to a deprecated function is a failed
   build, which is the right answer.
2. **Three minors of warning.** Three minor releases ship with the deprecation before the
   release that removes the entry: deprecated in `0.6.0`, it may be removed once `mix.exs` —
   the latest release — reads `0.8.0`, so `0.6`, `0.7` and `0.8` shipped with the warning and
   the removal ships in `0.9.0`. An entry deprecated on `0.x` and still present at `1.0.0` is
   on the `1.0.0` surface and waits like any `1.x` entry: three minors of the new major
   (`mix.exs` at `1.3.0`). The same count holds on `1.x`, where the release that carries the
   removal is a major, and that number — as any release number — is the release's to set, not
   the census's to check.
3. **Removal, on the record.** The writer marks the line `removed_in=Unreleased`, and the
   CHANGELOG names the entry again, in the release that removes it.

**A `0.x` break may skip the wait, said in so many words.** While the package is `0.x` an
entry may be removed, renamed or have its arity or defaults changed without three minors of
`@deprecated` if the CHANGELOG bullet that names it says it is a **documented break at the
minor** — the README's phrase for what `0.x` does — under a **BREAKING** heading whose section
carries the "How to tell whether you are affected" sentence. A first-time `@deprecated` in the
same change as the deletion does not count as the wait. From `1.0.0` there is no such skip:
the census reads `mix.exs`'s major, so the sentence stops counting the moment `1.0.0` has
shipped (the cycle that cuts `1.0.0` itself still reads `0.x` and may use it, as SemVer
allows before the first stable release).

**A docs-hidden flip is a removal.** `@doc false` on a public entry, or `@moduledoc false` on
a public module, takes it off the surface a consumer can rely on, and is treated exactly as a
deletion: `removed_in` on the line, the CHANGELOG naming it, and the same wait or the same
`0.x` sentence. There is no silent hide.

**How this compares.** Elixir itself deprecates in three steps — a soft deprecation in the
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

1. The baseline moves with it — a new line for an addition, a marker for a deprecation or a
   removal (the writer does both).
2. The CHANGELOG's Unreleased section names the exact `Module.name/arity`, the arity ending
   there (a type or callback may carry its `t:`/`c:` prefix). Not the name alone; not the
   module alone.
3. The kind-specific condition:
   - **still present, leaving later:** `@deprecated` on the entry and `deprecated_since` on
     its line, and the bullet that names it records a deprecation;
   - **removed, renamed, or arity or defaults changed:** `removed_in` on its line, and either
     `deprecated_since` naming a release three minors back, or — on `0.x` only — the bullet
     says *documented break at the minor* under a BREAKING heading with the how-to-tell
     sentence;
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
