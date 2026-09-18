<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Succession

What happens to this package if its one maintainer stops. Stated as it is, so a consumer
can weigh it, and so a successor knows where everything is.

## The bus factor is one

There is one maintainer (`docs/governance.md`). They hold the ScriptKittyOS organization
that owns the repository, the Hex package's owner account, the address in `SECURITY.md`, and
the key that signs nothing — this package signs no bytes of its own (`docs/crypto-posture.md`);
release attestations are made by GitHub's workflow identity, not by a personal key, so there
is no signing key to inherit.

## What survives the maintainer today, and what does not

**Survives:** the public repository under the organization (not under a personal account, so
a successor is added by the organization's owners rather than by transferring a personal
repository); the published Hex releases and their documentation on hexdocs, which stay
fetchable whether or not anyone maintains the package; the attestations on GitHub's store
and in Sigstore's log for every tagged release after `0.5.0`; the CHANGELOG, `UPGRADING.md`,
`docs/api-stability.md` and `docs/public-api.txt`, which say what a consumer may rely on
without asking anyone.

**Does not survive an account loss:** the private records — the slice plans, findings, review
archives and the gap ledger — live in a second repository under the maintainer's account, and
the **off-account archive is not in place**. A copy of the private repository outside GitHub
(an encrypted, object-locked off-site copy, with its key handling) is a decision the
maintainer has recorded as open and not yet taken; until it is, the private history survives
disk loss and not account loss. This page will say when that
changes, and not before.

## What a successor needs

1. **Organization ownership** of `ScriptKittyOS`, granted by its current owner, which gives
   the repository, its ruleset and its Actions.
2. **Hex package ownership**: `mix hex.owner add beam_mcp <email>` run by the current owner,
   or hex.pm's support process for an unreachable owner, which the package's public metadata
   (`mix.exs`, this page) supports.
3. **The release procedure**, which is in the tree: `tools/release_tarball.sh` builds the
   canonical tarball, the tag triggers `.github/workflows/provenance.yml`, and
   `docs/api-stability.md` names the step that writes release numbers into
   `docs/public-api.txt`. No step needs a secret beyond the Hex API key the owner holds.
4. **The review discipline**, which is in `CONVENTIONS.md` and `CONTRIBUTING.md`: the tier
   rule, the gate, the signoff tool. A successor who keeps running `tools/gate.sh` and reading
   the CHANGELOG's rules inherits the package's promises intact; the private records would
   help and are not required.
5. **The security intake**: the address in `SECURITY.md` is the maintainer's; a successor
   replaces it in the same commit that adds their name to `CODEOWNERS`, and says so in the
   CHANGELOG.

## What a consumer should conclude

Pin with `~>` at three numbers, as the README says; read `UPGRADING.md` before raising it;
and know that if this package stops being maintained, what you have keeps working and what
you have been promised is written down, but no new release will come from anyone until the
steps above have been taken by someone.
