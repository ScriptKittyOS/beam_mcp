<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Build provenance

What is attested about the package hex.pm serves, what the attestation binds to, how to verify
it, and how to reproduce the bytes without trusting anyone. Where a sentence here and a
measurement disagree, the measurement is the record; the measurements are named.

## What is attested, and what it binds to

On every release tag, CI builds the Hex tarball and attests its SHA-256 with GitHub's
build-provenance attestation (SLSA build provenance, Sigstore-signed, held in the repository's
attestation store), naming the repository, the commit and the workflow that built it
(`.github/workflows/provenance.yml`). The outer tarball's SHA-256 **is** the "Package checksum"
hex.pm records, so the attested subject is the identifier a consumer already sees on the
package page. The owner tags and publishes; the workflow attests and never publishes.

## The bytes are canonical by construction, not by luck

`mix hex.build` packages the working tree as it lies, and two things about a working tree are
the machine's, not the commit's: each entry carries the file's on-disk **mode** (a checkout
under umask 002 gives `664`, under 022 gives `644`), and a directory named in `files:` is
walked in **readdir order** (ext4's per-filesystem hash order; tmpfs's another). Measured on
2026-09-17: one commit gave three checksums — this machine's tree, a umask-022 checkout, a
tmpfs checkout — with the same 39 files inside. A tarball built from a working tree is that
machine's; an attestation over it would describe bytes no other machine reproduces.

So the release tarball is built by one script on every seat — CI, the publisher, a stranger
reproducing it:

```sh
tools/release_tarball.sh v0.6.0 beam_mcp-0.6.0.tar
```

It `git archive`s the ref with `tar.umask=022` (every file `644` whatever the machine's umask,
and only tracked files — a draft under `docs/` cannot ship), extracts with permissions
preserved, resolves the lock's dependencies, and runs `mix hex.build` there; `mix.exs` names
its `files:` as globs, so the entry order is `Path.wildcard`'s sort and not a filesystem's.
Measured: the same commit built this way on ext4 and on tmpfs gave one tarball, byte for
byte, every entry `644`. A test builds it and pins the structure — the modes, the order, the
checksum — on every run of the suite.

**A release verifies only if it was published with the same script** (`--publish` runs
`mix hex.publish` from the canonical tree). The tag's run downloads the bytes hex.pm serves
and verifies the attestation against them; a release published from a working tree fails that
step, loudly, and carries an attestation that describes nothing on hex.pm. The order is
publish, then push the tag: on a tag the run treats a tarball hex.pm does not yet serve as a
failure, not as a pass.

## Verify a published tarball

```sh
v=0.6.0
curl -fsSLO "https://repo.hex.pm/tarballs/beam_mcp-${v}.tar"
gh attestation verify "beam_mcp-${v}.tar" --repo ScriptKittyOS/beam_mcp
```

`gh attestation` needs GitHub CLI 2.49 or newer (Ubuntu's packaged 2.45 does not have it —
measured here), and it is the verifier GitHub documents; the attestation is a Sigstore bundle
(`gh attestation download` fetches it; the repository's Actions tab lists each one under
*Attestations*), so another Sigstore verifier can read it, but no such path is measured here
and none is claimed. What a verifier proves: the tarball's digest is the one a run of
`provenance.yml` at a named commit of this repository produced, signed through Sigstore at the
time. What it does not prove:
anything about that commit's contents — that is the tree's own record (the gate, the review
record), reachable from the commit the attestation names.

## Reproduce the bytes

Trust nothing above; build it:

```sh
git clone https://github.com/ScriptKittyOS/beam_mcp && cd beam_mcp
tools/release_tarball.sh "v${v}" "rebuilt-${v}.tar"     # prints the sha256 = the package checksum on hex.pm
```

The script needs Elixir, Erlang, Hex 2.x, bash, git and `sha256sum` or `shasum`. CI builds
with the pair `.tool-versions` names, copied into the workflow (Elixir 1.18 on OTP 28); the
tarball carries no compiled code, and Hex is what packages it — 2.4.0 and 2.5.1 gave
byte-identical tarballs of one commit (measured), and a packaging change in a later Hex would
show as a checksum the tag's run fails to match, not as a silent difference. The canonical
bytes assume ASCII file names: a non-ASCII name is encoded by the machine's locale, and a test
holds every packaged name to ASCII.

## Releases before this page

`0.5.0` and earlier carry no attestation and were built from working trees: their bytes are
the publishing machine's (the 0.5.0 tarball's entries carry `664`), reproducible on that
machine — measured for 0.5.0 — and not by the script above, which builds `644` entries in glob
order. Their provenance is the tag and the checksum, nothing more.

## Hex's own transparency log

When Hex ships a native transparency log for releases, this page moves the verification to it
and keeps the GitHub attestation as the second witness; nothing about what is attested changes,
since the subject is already the checksum Hex records.
