<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Upgrading

From any `0.x` to the next, and what `1.0` will ask. The policy this follows is
`docs/api-stability.md`; the surface it applies to is `docs/public-api.txt`; every break below
has its full entry, with a "how to tell whether you are affected" sentence, in `CHANGELOG.md`.

## The rule for `0.x`

Breaks land at the **minor** position and nowhere else. Pin `~> 0.5.0` (the current minor,
three numbers), not `~> 0.5`: the tighter pin stops at the next minor, which is where the
next documented break can be, so a routine `mix deps.update` never carries you across one.
To move a minor: read the release's `### Changed — BREAKING` entries, apply the "how to tell"
sentence of each to your host, then raise the pin.

## The breaks so far, one line each

| release | where it breaks | what to do |
| --- | --- | --- |
| `0.2.0` | the wire, for clients whose `_meta` names `2025-11-25` | results no longer carry `resultType` or `_meta.io.modelcontextprotocol/serverInfo`; a client reading either must stop |
| `0.3.0` | the transport set | the HTTP transport arrives as an optional dependency pair (`plug`, `bandit`); a stdio-only host changes nothing; an HTTP host supplies the two options that have no defaults |
| `0.4.0` | the host contract | `BeamMCP.ToolCatalog` is replaced by `BeamMCP.Catalog`, `all/0` by `capabilities/0`; every catalog implementation changes |
| `0.5.0` | the wire, the exported bytes, the host contract | a request's `_meta` is read at `params._meta` and refused at the top level; the sign vocabulary renames the one sign the package writes and `schema_version` becomes `2`; a catalog's `resources` and `prompts` lists must hold the package's structs |
| next minor (unreleased) | the exported bytes | the canonical envelope names its `algorithm` and `schema_version` becomes `3`; a verifier that pins `schema_version: 2` or hashes without reading the algorithm must be updated (`docs/connectome-canonical.md`, "Versions") |

The next minor also raises the OTP floor's stated reason (OTP 27's trace sessions, which the
connectome tracer now runs in) — not a new floor: 27 was already the floor — and changes what
the tracer does beside a host's own tracer (`docs/connectome-observed.md`); neither removes,
renames or hides a public entry.

## What `1.0` will ask

The `1.0.0` release freezes `docs/public-api.txt` as it stands at that release: from then on
an incompatible change to any line of it waits for `2.0.0`, and a deprecation warns for three
minors before the removal that only a major may carry. `1.0` is cut after the assessability
release (`0.8.0`) and the governance, threat-model and posture pages that precede it, and
after the frozen surface has stood unchanged across at least one minor. What a `0.x`
consumer must do to reach it is, today, nothing beyond the minors above: no entry is
deprecated at the time of writing (`docs/public-api.txt` carries no `deprecated_since`
marker), so there is no removal to prepare for. Each `0.x` release after this page adds its
row to the table above and, if it deprecates an entry, names the replacement here.
