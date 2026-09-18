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
`@moduledoc` is present is public unless its own `@doc` is `false`. A missing `@doc` is still
listed and still public: hiding is explicit, never an accident of omission. A module with
`@moduledoc false` is private surface — callable, since the BEAM hides nothing, but unpromised:
it can change or go in any release with no entry. Today no module under `lib/` is private —
every one of the 26 carries a `@moduledoc` — and `docs/public-api.txt` lists their 128 public
entries as of this page's writing; the file is written by a command from the compiled
application, never by hand:

    MIX_ENV=test mix run -e "BeamMCP.PublicAPI.write_baseline!()"

The baseline is a tracked file in the package. Its grammar is one line per entry,
`Module kind name/arity`, followed by markers the census reads:

| marker | meaning |
| --- | --- |
| `since=V` | added while `mix.exs` read version `V` |
| `deprecated_since=V` | `@deprecated` first shipped while `mix.exs` read `V` |
| `removed_in=V` | left the public surface while `mix.exs` read `V` — a deletion, a rename, an arity change, or a `@doc false` |

A line changes state; it is not deleted. The tree carries what left and when, and the census
reads the tree, never git history. (A line deleted outright is invisible to a tree-only census
— the same as deleting any pinned list — and is a reviewer's line, not this page's promise.)

**Three things are promised separately, by their own pages, not by this one:** the wire —
which protocol revisions the transports serve and what each request is answered with
(`README.md`); the exported bytes — the canonical envelope's `schema_version` and its
`algorithm`, whose history and verifier consequences are in `docs/connectome-canonical.md`
and `docs/connectome-diff.md`; and the host contract — the `BeamMCP.Catalog` behaviour, whose
callbacks are public entries here, and the options the transports and the tracer take,
documented on the functions that take them — both the subject of the README's "how to tell
whether you are affected" sentences. Not promised anywhere: the
shape of `inspect/1` output, the text of log lines and error messages, the names of the
tracer's processes and trace session, and the layout of the observed collector's ETS rows
beyond the `row/0` type `BeamMCP.Connectome.Observed` documents.

## Versioning

**While the package is `0.x`, breaks land at the minor position** and are documented as such:
each is a `### Changed — BREAKING` CHANGELOG entry with a "how to tell whether you are
affected" sentence. That is why the README recommends `~> 0.5.0` rather than `~> 0.5`: the
tighter pin stops at the next minor, which is where the next documented break can be. Patch
releases carry no break to the public surface, the wire, the exported bytes or the host
contract.

**From `1.0.0`, the package follows semantic versioning:** the public surface listed in
`docs/public-api.txt` at `1.0.0` changes incompatibly only at a major; a minor adds and
deprecates; a patch fixes. The 1.0 cut is its own release (the release after the assessability
release, `0.8.0`, and the governance and threat-model pages that precede it); `UPGRADING.md`
carries what a `0.x` consumer must do to reach it.

## Deprecation: three steps, three minors

A public entry that is going to leave goes in three steps, each on the record:

1. **`@deprecated`, with the replacement already shipped.** The function carries
   `@deprecated "use ..."` — the compiler warns every caller at their compile — its baseline
   line gains `deprecated_since=V`, and the CHANGELOG's Unreleased section names the exact
   `Module.name/arity` in a bullet that records the deprecation and its replacement. The
   replacement exists in the same release or an earlier one; a deprecation that points at
   nothing is not one.
2. **Three minors of warning.** On `0.x`, an entry deprecated while `mix.exs` read `0.5.0`
   (so the deprecation ships in `0.6.0`) may be removed in a cycle whose `mix.exs` reads
   `0.8.0` or later — `0.6`, `0.7` and `0.8` ship with the warning. On `1.x` and later the
   removal waits for the next major, however many minors pass.
3. **Removal, on the record.** The baseline line gains `removed_in=V`, and the CHANGELOG names
   the entry again, in the release that removes it.

**A `0.x` break may skip the wait, said in so many words.** While the package is `0.x` an
entry may be removed, renamed or have its arity changed without three minors of `@deprecated`
if the CHANGELOG bullet that names it says it is a **documented break at the minor** — the
README's phrase for what `0.x` does — and the release is a minor. A first-time `@deprecated`
in the same change as the deletion does not count as the wait. From `1.0.0` there is no such
skip.

**A docs-hidden flip is a removal.** `@doc false` on a public entry, or `@moduledoc false` on
a public module, takes it off the surface a consumer can rely on, and is treated exactly as a
deletion: `removed_in` on the line, the CHANGELOG naming it, and the same wait or the same
`0.x` sentence. There is no silent hide.

## The census, exactly

The census compares the compiled application's documentation chunks with
`docs/public-api.txt` and both with the CHANGELOG's Unreleased section. A documented public
entry may change only if **all** of the following hold in the same change:

1. The baseline moves with it — a new line for an addition, a marker for a deprecation or a
   removal.
2. The CHANGELOG's Unreleased section names the exact `Module.name/arity` (a type or callback
   may carry its `t:`/`c:` prefix). Not the name alone; not the module alone.
3. The kind-specific condition:
   - **still present, leaving later:** `@deprecated` on the entry and `deprecated_since=V`
     on its line, and the bullet that names it records a deprecation;
   - **removed, renamed, or arity changed:** `removed_in=V` on its line, and either
     `deprecated_since` three minors behind (`0.x`) or a major behind (`1.x`), or — on `0.x`
     only — the bullet says *documented break at the minor*;
   - **docs-hidden:** as a removal.

Each kind has its one condition set; there is no OR between them. "`V`" is `mix.exs`'s
version at the time of the change; a marker whose version equals it is this cycle's and is
held to the Unreleased section, and the release bump makes it historic.

What the census showed red before it was trusted, each with the baseline unchanged unless
said: a public function deleted; renamed; hidden with `@doc false`; removed with the baseline
moved and the CHANGELOG silent; the same with a sibling deprecated instead; removed with the
CHANGELOG naming it but the `@deprecated` first added in the same change; `@deprecated` with no
marker; with the marker and no bullet; the marker with no `@deprecated`. And green: removed
with the CHANGELOG naming it and three minors of `deprecated_since` on the tree; removed with
the CHANGELOG naming it and the `0.x` sentence; deprecated with the attribute, the marker and
the bullet.
