<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Upgrading

From any `0.x` to the next, and what `1.0` will ask. The policy this follows is
`docs/api-stability.md`; the surface it applies to is `docs/public-api.txt`; every break below
has its full entry in `CHANGELOG.md` under the heading the table names: from `0.5.0` on with
a "how to tell whether you are affected" sentence, and from `0.6.0` on under a heading that
says **BREAKING**, which the census requires.

## The rule for `0.x`

Breaks land at the **minor** position and nowhere else. Pin `~> 0.10.0` (the current minor,
three numbers), not `~> 0.10`: the tighter pin stops at the next minor, which is where the
next documented break can be, so a routine `mix deps.update` never carries you across one.
To move a minor: read the release's rows below and their CHANGELOG entries, apply each "how
to tell" sentence to your host, then raise the pin.

## The breaks so far, one line each

| release | where it breaks | CHANGELOG heading | what to do |
| --- | --- | --- | --- |
| `0.2.0` | the wire, for clients whose `_meta` names `2025-11-25` | "Changed: two fields are REMOVED from results for legacy-declared requests" | results no longer carry `resultType` or `_meta.io.modelcontextprotocol/serverInfo`; a client reading either must stop |
| `0.3.0` | the wire, on `tools/list`, and an addition placed at the minor by policy | "Added: `ttlMs` and `cacheScope` on `tools/list`" and "Added: stateless Streamable HTTP transport" | `tools/list` results carry the `ttlMs`/`cacheScope` fields `2026-07-28` requires; the HTTP transport arrives as an optional dependency pair (`plug`, `bandit`): a stdio-only host changes nothing, an HTTP host supplies the two options that have no defaults |
| `0.4.0` | the host contract | "Changed: BREAKING, and it breaks a host contract rather than the wire" | `BeamMCP.ToolCatalog` is replaced by `BeamMCP.Catalog`, `all/0` by `capabilities/0`; every catalog implementation changes |
| `0.5.0` | the wire, the exported bytes, the host contract | "Changed (BREAKING): the request `_meta` …", "Changed (BREAKING): the sign vocabulary …", and the structs requirement under the "Added: the resources primitive" and "Added: the prompts primitive" entries | a request's `_meta` is read at `params._meta` and refused at the top level; the sign vocabulary renames the one sign the package writes and `schema_version` becomes `2`; a catalog's `resources` and `prompts` lists must hold the package's structs |
| `0.6.0` | the exported bytes | "Changed (BREAKING, the exported bytes): the canonical envelope names its algorithm; `schema_version` 3 …" | a verifier that pins `schema_version: 2` or hashes without reading the algorithm must be updated (`docs/connectome-canonical.md`, "Versions") |
| `0.9.0` | nothing breaks: two additions placed at the minor by policy | "Added: the server seam, `:server` on both transports, a module above the core" and "Added: the scheme beside the signature, `scheme:` and `key_id:` in `signature/3`'s return" | a host that passes no `:server` and reads no `scheme:` changes nothing; a host putting a wrapper above the core passes its module under `:server` (`@behaviour BeamMCP.Server`; HTTP reaches `new/1` and `handle_message/2`, stdio those and `shutdown?/1`); a host matching `signature/3`'s return exactly reads five members now, the two new ones `nil` unless it passed them |

`0.6.0` also restates the OTP floor's reason (OTP 27's trace sessions, which the connectome
tracer now runs in), not a new floor (27 was already the floor), and changes what the tracer
does beside a host's own tracer (`docs/connectome-observed.md`); neither removes, renames or
hides a public entry.

**`0.7.0` has no row: it breaks nothing.** It adds the signer seam, `BeamMCP.Signer` (one
callback, `sign/2`), `BeamMCP.Signer.None` and `BeamMCP.Connectome.Canonical.signature/3`,
under "Added: the signer seam" in the CHANGELOG. A host that does not sign changes nothing;
one that does adds the separate package `beam_mcp_signer` and passes its module and key to
`signature/3`. Raise the pin to `~> 0.7.0` when you take it; `~> 0.6.0` stops before it by the
rule, not because anything moved.

**`0.8.0` has no row either: it is the quiet minor.** No public entry was added, removed,
renamed, hidden or changed in arity (`docs/public-api.txt` is line for line `0.7.0`'s, and the
release step wrote nothing into it), and no wire byte or envelope byte moved. What changed is
instruments (the gate diffs the baseline against `origin/main`; the pull-request summary waits
for running legs) and pages (the Scorecard's measured figures on the governance page). Raise
the pin to `~> 0.8.0`. **A host on `beam_mcp_signer` waits for that package's release that
admits `0.8.0`**: its `0.1.0` requires `beam_mcp ~> 0.7.0` (three numbers, by the same rule as
this page's pin), so `{:beam_mcp, "~> 0.8.0"}` beside `{:beam_mcp_signer, "~> 0.1.0"}` does not
resolve until it does. That is the cost of the three-number pin, paid once per minor, on the
signer's side. *Appended 2026-09-21:* that release exists: `beam_mcp_signer` `0.1.1`
(2026-09-19) requires `~> 0.7`, two numbers, so it resolves beside `~> 0.8.0` and `~> 0.9.0`
alike; the paragraph above is history and the cost it names was paid once.

**`0.9.0` has a row above, and it is not a break.** Two additions at the minor: `:server` on
`BeamMCP.Transport.HTTP` and `BeamMCP.Transport.Stdio.run/1` (default `BeamMCP.Server`, which is
now the behaviour a wrapper implements: `new/1`, `handle_message/2`, and `shutdown?/1` optional),
and `scheme:` and `key_id:` beside the signature `BeamMCP.Connectome.Canonical.signature/3`
returns, copied from the host's options and verified by nothing here; the canonical bytes and
`schema_version` do not move. Raise the pin to `~> 0.9.0`. A host on `beam_mcp_signer` `0.1.1`
(requirement `~> 0.7`) resolves beside `{:beam_mcp, "~> 0.9.0"}` without a signer release.

**`0.10.0` has no row: it is the quiet minor again.** No public entry was added, removed,
renamed, hidden or changed in arity (`docs/public-api.txt` did not move, and the release step
wrote nothing into it), and no wire byte or envelope byte moved. What changed is instruments
and pages: the suite runs in FIPS mode in CI on the validated OpenSSL provider, each release
carries an attested SBOM, `docs/fips.md` reads measurements, and the pages are free of em
dashes, the CHANGELOG's released headings included (the quotations below and above follow them).
Raise the pin to `~> 0.10.0`. `beam_mcp_signer` `0.1.1` and `0.2.0` (requirement `~> 0.7`)
resolve beside it without a signer release.

## The road to `1.0.0`, in order

Stated here so nobody infers it from a plan's label or a folder's name:

1. **`0.6.0`**, everything since `0.5.0`, the assessability snapshot. One documented break at
   the minor (the exported bytes).
2. **`0.7.0`**, the signer seam, `BeamMCP.Signer` (a behaviour added to the public
   surface; no authority passes through it), the last intentional addition before `1.0.0`.
   An addition, not a break; `~> 0.6.0` stops at it all the same, by the rule.
   *Superseded 2026-09-21, appended not edited:* it was not the last: `0.9.0` adds the
   `:server` seam and the scheme members, because a consumer's composed system needs the seam
   from this package before `1.0.0` can be an honest freeze; the stand at `0.8.0` ended for
   that reason and no other.
3. **`0.8.0`**, the quiet minor. Documentation, the Scorecard's rows,
   instrument leftovers. No public entry added, removed, renamed or hidden: the "full minor
   release unchanged" the README's `1.0.0` condition requires, measured by
   `docs/public-api.txt` not moving (the gate now diffs it against `origin/main` on every run).
4. **`0.9.0`**: the `:server` seam on both transports and `scheme:`/`key_id:`
   beside the signature. Two additions, no break; four public entries added; the clock the
   README's condition names restarts here.
5. **`0.10.0`**, this release, the quiet minor again: instruments and pages (the suite in FIPS
   mode in CI, an attested SBOM at release, the em-dash sweep), no public entry moved.
6. **`1.0.0`**, after `0.10.0` has stood: the surface frozen as `docs/api-stability.md` says.

## What `1.0` will ask

The `1.0.0` release freezes `docs/public-api.txt` as it stands at that release: from then on
an incompatible change to any line of it ships only in a major, after three minors of
`@deprecated` warning. The README states the condition for cutting it (`1.0.0` follows once
the public API and the stated threat model have each survived a full minor release unchanged)
and nothing here adds to it. The cycle that cuts `1.0.0` itself still reads `0.x` in
`mix.exs`, so it may still use the `0.x` documented-break sentence, as SemVer allows before
the first stable release; that release's row will say so if it does. What a `0.x` consumer
must do to reach `1.0` is, today, nothing beyond the minors above: no entry is deprecated at
the time of writing (`docs/public-api.txt` carries no `deprecated_since` marker), so there is
no removal to prepare for. Each `0.x` release after this page adds its row to the table above
and, if it deprecates an entry, names the replacement here.
