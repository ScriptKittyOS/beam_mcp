#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# The release tarball, built the one way that gives the same bytes on every machine.
#
#     tools/release_tarball.sh <ref> <out.tar>             build; print the checksum
#     tools/release_tarball.sh <ref> <out.tar> --publish   the same, then `mix hex.publish` FROM
#                                                          THAT TREE, so what is published is
#                                                          what was built and attested
#
# WHY A SCRIPT. `mix hex.build` packages the working tree as it lies: each entry carries the
# file's ON-DISK MODE (umask 002 gives 664, umask 022 gives 644 -- two checksums for one commit),
# and a directory named in `files:` is walked in readdir order (fixed by globs in mix.exs, not
# here). A review lane measured both on 2026-09-17: the same commit gave 5880f777... from a
# umask-022 checkout and c23ad0c7... from this machine's. So the bytes are made canonical BY
# CONSTRUCTION: the tree is `git archive`'d at the ref with `tar.umask=022` (every regular file
# 644 whatever the machine's umask, and only TRACKED files -- a draft under docs/ cannot ship),
# extracted with permissions preserved, the lock's dependencies resolved, and built there. CI
# runs this on the release tag and attests the result; the publisher runs it with --publish;
# a stranger runs it to reproduce the checksum hex.pm shows. One instrument, three seats.
#
# What it does not do: pin Hex. The runner's Hex is what erlef/setup-beam installs; the
# publisher's is theirs. Hex 2.x has packaged the same bytes across the versions measured
# (2.5.1 here); a packaging change in Hex is caught by the workflow's checksum comparison, not
# hidden by this script.
set -euo pipefail
ref=${1:?ref (a tag or commit)}; out=${2:?output tarball path}; publish=${3:-}
[ -z "$publish" ] || [ "$publish" = "--publish" ] || { echo "third argument is --publish or nothing" >&2; exit 2; }
out=$(realpath -m "$out")
root=$(git rev-parse --show-toplevel)
work=$(mktemp -d "${TMPDIR:-/tmp}/beam_mcp-release.XXXXXX"); trap 'rm -rf "$work"' EXIT
git -C "$root" -c tar.umask=022 archive --format=tar "$ref" | tar -xp -C "$work"
cd "$work"
mix deps.get >/dev/null
mix hex.build -o "$out" | tee "$work/build.out"
sha=$(sha256sum "$out" | cut -d' ' -f1)
grep -q "Package checksum: ${sha}" "$work/build.out" \
  || { echo "the tarball's sha256 ${sha} is not the checksum hex printed" >&2; exit 1; }
echo "release tarball ${out}: sha256 ${sha} (= hex's package checksum) from ${ref} = $(git -C "$root" rev-parse "$ref")"
if [ "$publish" = "--publish" ]; then
  mix hex.publish
fi
