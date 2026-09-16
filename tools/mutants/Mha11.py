# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code a path.
# Mha11 -- the surface encodes and hashes the diff record under the default while keying the hex by the option (lane a's surviving plant d)
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = """         {:ok, bytes} <- Diff.encode(diff, algorithm: algorithm),
         {:ok, hash} <- Diff.hash(diff, algorithm: algorithm),"""
new = """         {:ok, bytes} <- Diff.encode(diff, algorithm: elem({:sha256, algorithm}, 0)),
         {:ok, hash} <- Diff.hash(diff, algorithm: elem({:sha256, algorithm}, 0)),"""
assert s.count(old) == 1, "anchor not found once: %d" % s.count(old)
s = s.replace(old, new)
io.open(p, "w", encoding="utf-8").write(s)
