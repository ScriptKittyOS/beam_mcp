<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Build provenance

What is attested about the package hex.pm serves, what the attestation binds to, how to verify
it, and how to reproduce the bytes without trusting anyone. Where a sentence here and a
measurement disagree, the measurement is the record; the measurements are named.

## What is attested, and what it binds to

On every release tag, CI builds the Hex tarball with `mix hex.build` and attests its SHA-256
with GitHub's build-provenance attestation (SLSA build provenance, Sigstore-signed, held in the
repository's attestation store), naming the repository, the commit and the workflow that built
it (`.github/workflows/provenance.yml`). The owner tags and publishes; the workflow attests and
never publishes.

The attested digest is the identifier a consumer already sees. `mix hex.build` is
byte-deterministic — the tar's entries carry fixed mtimes and uid 0 — and **the outer
tarball's SHA-256 is the "Package checksum" hex.pm records**. Measured on 2026-09-17: three
builds of one tree, one after an mtime bump, gave one digest; the tarball rebuilt from the
`v0.5.0` tag was byte-identical to the one `repo.hex.pm` serves for 0.5.0
(`c95d7b2a2a9113bfa5641ea8a42de1e30af8dc813cadb70c76297aa54290911e`, the checksum on the
package page). So an attestation over a tag's tarball describes the bytes hex.pm serves for
that version, and the workflow's last step checks exactly that: it downloads the published
tarball fresh and verifies the attestation against it — or says NOT MEASURED when hex.pm does
not serve that version yet, which is what a run on an unpublished commit is.

## Verify a published tarball

```sh
v=0.6.0
curl -fsSLO "https://repo.hex.pm/tarballs/beam_mcp-${v}.tar"
gh attestation verify "beam_mcp-${v}.tar" --repo ScriptKittyOS/beam_mcp
```

`gh attestation` needs GitHub CLI 2.49 or newer (Ubuntu's packaged 2.45 does not have it —
measured here). Without `gh`, `slsa-verifier` reads the same bundle:
`gh attestation download` fetches it, or the attestation's page under the repository's
*Attestations* tab links it. What a verifier proves: the tarball's digest is the one a run of
`provenance.yml` at a named commit of this repository produced, signed through Sigstore at the
time. What it does not prove: anything about that commit's contents — that is the tree's own
record (the gate, the review record), reachable from the commit the attestation names.

## Reproduce the bytes

Trust nothing above; build it:

```sh
git clone https://github.com/ScriptKittyOS/beam_mcp && cd beam_mcp
git checkout "v${v}"
mix deps.get && mix hex.build -o "rebuilt-${v}.tar"
sha256sum "rebuilt-${v}.tar"          # equals the package checksum on hex.pm
```

The pair CI builds with is `.tool-versions`' (Elixir 1.18 on OTP 28); the tarball carries no
compiled code, so a different pair reproduces the same bytes as long as `mix hex.build`'s
packaging is the same Hex (2.x), which is what the 0.5.0 rebuild above measured.

## Releases before this page

`0.5.0` and earlier carry no attestation: the workflow did not exist when they were cut. Their
bytes reproduce from their tags exactly as above — the 0.5.0 measurement is the evidence — and
that reproduction is the only provenance they have.

## Hex's own transparency log

When Hex ships a native transparency log for releases, this page moves the verification to it
and keeps the GitHub attestation as the second witness; nothing about what is attested changes,
since the subject is already the checksum Hex records.
