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
# ONE WORKAROUND, NAMED (G-087). mix_sbom 0.11.0 crashes on the `tools: :optional` entry in
# mix.exs's `extra_applications` (FunctionClauseError in its normalize_dep/1; Mix documents
# the `{app, :optional}` form). In the scratch copy only, that one entry is rewritten to
# `:tools` before the tool reads it; the shipped mix.exs is untouched and the component list is
# the same. The step refuses to run if the line is not the one it expects, so a changed mix.exs
# is noticed rather than silently mis-read. Remove it when a mix_sbom release reads the form.
#
# Not byte-reproducible by design: CycloneDX gives every document a fresh serialNumber and a
# timestamp. What binds it is the attestation over the tarball's digest (provenance.yml).
# Needs bash, git, curl, sha256sum, and Elixir/Mix for `mix deps.get`.
set -euo pipefail
ref=${1:?ref (a tag or commit)}; out=${2:?output path}
case "$out" in /*) ;; *) out="$PWD/$out" ;; esac

version=0.11.0
digest=db1982c8599f9383c48e6bb61cd4dc7305d2afdf48273568839b7f1dc0d572de

root=$(git rev-parse --show-toplevel)
work=$(mktemp -d "${TMPDIR:-/tmp}/beam_mcp-sbom.XXXXXX"); trap 'rm -rf "$work"' EXIT

bin="$work/mix_sbom"
curl -fsSL -o "$bin" "https://github.com/erlef/mix_sbom/releases/download/v${version}/mix_sbom_Linux_X64"
echo "${digest}  ${bin}" | sha256sum -c - >/dev/null \
  || { echo "mix_sbom ${version}: the binary's sha256 is not the release asset's" >&2; exit 1; }
chmod +x "$bin"

mkdir "$work/src"
git -C "$root" -c tar.umask=022 archive --format=tar "$ref" | tar -x -C "$work/src"

expected='    [extra_applications: [:logger, :crypto, tools: :optional]]'
grep -qxF -- "$expected" "$work/src/mix.exs" \
  || { echo "mix.exs no longer has the extra_applications line the G-087 workaround rewrites" >&2; exit 1; }
sed -i 's/^    \[extra_applications: \[:logger, :crypto, tools: :optional\]\]$/    [extra_applications: [:logger, :crypto, :tools]]/' "$work/src/mix.exs"

(cd "$work/src" && mix deps.get >/dev/null)
"$bin" cyclonedx --only prod --format json --schema 1.6 --force --output "$out" "$work/src" >/dev/null

components=$(grep -o '"bom-ref"' "$out" | wc -l | tr -d ' ')
echo "sbom ${out}: CycloneDX 1.6, ${components} bom-refs, from ${ref} = $(git -C "$root" rev-parse "${ref}^{commit}") (mix_sbom ${version})"
