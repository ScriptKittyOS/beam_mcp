#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# The release's software bill of materials (CycloneDX 1.6, JSON), generated OUTSIDE mix.exs.
#
#     tools/sbom.sh <ref> <out.cdx.json>
#
# WHY OUTSIDE mix.exs. The owner's constraint for the SBOM (2026-09-17): the EEF's tool, not a
# dependency of this package; nothing added to mix.lock just to have a file; the file attached at
# release, not kept in the tree. So this runs the EEF's self-contained binary (erlef/mix_sbom,
# the Hex package `sbom`), pinned by version and by the SHA-256 GitHub records for the release
# asset, against a `git archive` of the ref (the same tree tools/release_tarball.sh packages),
# after `mix deps.get` there, so the lock's resolved versions are what it reads. `--only prod`:
# the runtime dependency set a host inherits (plug and bandit included, though optional in
# mix.exs -- the tool has no notion of an optional dependency and marks them required).
#
# No workaround. mix_sbom 0.11.0 crashed on the `tools: :optional` entry in mix.exs's
# `extra_applications` (FunctionClauseError in its normalize_dep/1), and this script rewrote that
# one line in a scratch copy. 0.12.0 reads the form (erlef/mix_sbom#157, fixed by #169),
# so the tool now reads the tree exactly as it is tagged.
#
# Not byte-reproducible by design: CycloneDX gives every document a fresh serialNumber and a
# timestamp. What binds it is the attestation over the tarball's digest (provenance.yml).
# Needs bash, git, curl, sha256sum, and Elixir/Mix for `mix deps.get`.
set -euo pipefail
ref=${1:?ref (a tag or commit)}; out=${2:?output path}
case "$out" in /*) ;; *) out="$PWD/$out" ;; esac

version=0.12.0
digest=5da833839dd80350e15ca5c2b02f233e0917dc4333efa520994acf0ed9cab19b

root=$(git rev-parse --show-toplevel)
work=$(mktemp -d "${TMPDIR:-/tmp}/beam_mcp-sbom.XXXXXX"); trap 'rm -rf "$work"' EXIT

bin="$work/mix_sbom"
curl -fsSL -o "$bin" "https://github.com/erlef/mix_sbom/releases/download/v${version}/mix_sbom_Linux_X64"
echo "${digest}  ${bin}" | sha256sum -c - >/dev/null \
  || { echo "mix_sbom ${version}: the binary's sha256 is not the release asset's" >&2; exit 1; }
chmod +x "$bin"

mkdir "$work/src"
git -C "$root" -c tar.umask=022 archive --format=tar "$ref" | tar -x -C "$work/src"

(cd "$work/src" && mix deps.get >/dev/null)
"$bin" cyclonedx --only prod --format json --schema 1.6 --force --output "$out" "$work/src" >/dev/null

components=$(grep -o '"bom-ref"' "$out" | wc -l | tr -d ' ')
echo "sbom ${out}: CycloneDX 1.6, ${components} bom-refs, from ${ref} = $(git -C "$root" rev-parse "${ref}^{commit}") (mix_sbom ${version})"
