<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Succession

What happens to this package if its one maintainer stops. Stated as it is, so a consumer
can weigh it, and so a successor knows where everything is.

## The bus factor is one

There is one maintainer (`docs/governance.md`): one person has written and reviewed this code,
and that knowledge is not held twice. They hold the ScriptKittyOS organization that owns the
repository, the Hex package's `full` ownership, the address in `SECURITY.md`, and the OpenPGP
key that signs release tags (`docs/provenance.md`). The package itself signs no bytes
(`docs/crypto-posture.md`) and release attestations are made by GitHub's workflow identity, so
the tag key is the only personal key, and a successor signs with their own rather than
inheriting it. **Access is no longer held by one person alone**: see the next section.

## Two people with access

From 2026-09-23 the project can go on within a week if the maintainer cannot, through two
people:

- **`znmead`** holds the **Maintain** role on this repository: he can triage, label and close
  issues, rebase-merge a pull request once the ruleset's required checks are green (the ruleset
  requires no approving review), and push a release tag, which runs
  `.github/workflows/provenance.yml`.
- **Mike Hostetler** (`mikehostetler` on GitHub and hex.pm) holds the same **Maintain** role
  here, and **maintainer** ownership of `beam_mcp` on hex.pm: he can publish a release, from the
  tag with `tools/release_tarball.sh` and `--publish`, and retire one. He alone can therefore
  carry every step from issue to published release.

The organization requires two-factor authentication with secure methods only (an
authenticator app, a security key or a passkey; not SMS) for everyone who can change the
repository.

Both hold the same on `beam_mcp_signer`. A release tag they sign is signed with their own
OpenPGP key, and the first such tag is announced in the CHANGELOG with its fingerprint, as
`docs/provenance.md` says of any change of key.

What their access does not reach, stated so it is not assumed: the repository's settings and
ruleset, adding collaborators, and adding owners on hex.pm stay with the maintainer (the
organization's owner, the package's `full` owner), and so does the security intake
`SECURITY.md` names. If the maintainer's account were lost for good, the two of them keep
issues, merges and releases going, and extending access to anyone else goes through GitHub
Support and hex.pm's support process.

## What survives the maintainer today, and what does not

**Survives:** the public repository under the organization — public and forkable whatever
happens to any account; if the maintainer *stops*, they add a successor as the organization's
owner first, which is a smaller act than transferring a personal repository; the published
Hex releases and their documentation on hexdocs, which stay fetchable whether or not anyone
maintains the package; the attestations on GitHub's store and in Sigstore's log for every
tagged release from `0.6.0` on (`0.5.0` and earlier carry none); the CHANGELOG, `UPGRADING.md`, `docs/api-stability.md` and `docs/public-api.txt`,
which say what a consumer may rely on without asking anyone.

**Does not survive an account loss:** control of the repository's settings and of who else
may write (write itself survives, above): the organization has one owner, the maintainer, so
if that account is lost no owner remains to add anyone and the path is GitHub Support's
orphaned-organization process, the same class of fallback named below for hex.pm; and the
private records (the slice plans, findings, review archives and the gap ledger), which live
in a second repository under the maintainer's account, and the
**off-account archive is not in place**. A copy of the private repository outside GitHub
(an encrypted, object-locked off-site copy, with its key handling) is a decision the
maintainer has recorded as open and not yet taken; until it is, the private history survives
disk loss and not account loss. This page will say when that
changes, and not before.

## What a successor needs

1. **Organization ownership** of `ScriptKittyOS`, granted by its current owner, which gives
   the repository, its ruleset and its Actions.
2. **Hex package ownership**: the package has two owners on hex.pm, `aylacroft` (`full`) and
   `mikehostetler` (`maintainer`, who can publish but not add owners);
   `mix hex.owner add beam_mcp <email>` run by the `full` owner, or hex.pm's support process
   for an unreachable one, which the package's public metadata (`mix.exs`, this page) supports.
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
