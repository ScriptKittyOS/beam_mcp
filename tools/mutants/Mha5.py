# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code a path.
# Mha5 -- hash/2 encodes with the default and digests with the option: bytes and hash disagree
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = """    with {:ok, bytes} <- encode(graph, algorithm: algorithm), do: {:ok, digest(algorithm, bytes)}"""
new = """    with {:ok, bytes} <- encode(graph), do: {:ok, digest(algorithm, bytes)}"""
assert s.count(old) == 1, "anchor not found once: %d" % s.count(old)
s = s.replace(old, new)
io.open(p, "w", encoding="utf-8").write(s)
