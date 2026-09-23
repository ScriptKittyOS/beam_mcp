<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Roadmap

What this project intends to do, and not do, over the next year (to September 2027). It
gathers what `UPGRADING.md`, the README and `docs/will-not-implement.md` already say into one
place. The order is firm; the dates are not promised. When this page and one of those
disagree, those are the record and this page is corrected.

## Next: `0.10.0`, the quiet minor

Instruments and pages, no public entry added, removed or changed:

- a FIPS leg in CI, exercising the package on a FIPS-mode OpenSSL (`docs/fips.md` states the
  posture today);
- a software bill of materials attached at each release, beside the provenance attestation
  (`docs/provenance.md`);
- a copy sweep of the documentation.

## Then: `1.0.0`, the freeze

`1.0.0` follows once the public API and the stated threat model have each survived a full
minor release unchanged (the README's condition). From `1.0.0`, `docs/public-api.txt` is
frozen as `docs/api-stability.md` describes: an incompatible change ships only in a major
version, after three minors of deprecation warnings. `UPGRADING.md` says what a `0.x`
consumer needs to do to reach it.

## After `1.0.0`: additions at the minor

Decided, in this order, each additive so no `1.x` consumer is broken by it:

1. **A federation seam**, for merging connectome graphs from several nodes. The trust
   questions it must answer first are listed in `docs/threat-model.md` ("Federation").
2. **Effective connectivity**: the observed graph weighted into the declared one.
3. **The Tasks extension** of the `2026-07-28` revision: not built today and not refused
   either; an addition, like the two above.

Throughout: security fixes on the latest minor as `SECURITY.md` commits, dependency updates
through Dependabot, and the protocol revisions the MCP specification publishes, tracked as
they are released.

## What this project will not do

These are decisions, not a backlog. Each is an entry on `docs/will-not-implement.md` with the
test that holds it:

- compute a verdict on an edge, hold a key, make a signature of its own, or decide authority
  (a signer that holds a key is the separate package `beam_mcp_signer`);
- hold a tool, a domain or a concrete catalog;
- issue or honour a session, carry OAuth, or act as an MCP client;
- put a payload byte into the observed graph, or claim a capability the specification does
  not define;
- enumerate all paths or match motifs in the connectome;
- run a multi-round-trip request.

Also out of scope for the year: tools, policy, risk tiers, approvals and receipts, which
belong to the applications that embed this package.

## How the roadmap changes

A change to the order or the scope is recorded here and in the CHANGELOG, in the pull request
that makes it. The maintainer decides (`docs/governance.md`); a proposal is an issue on the
repository.
