# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code a path.
# Mha2 -- hash_value/2 digests sha384 as SHA-256 over bytes that name sha384 (cut at a caller of digest/2, since the census reads that line as text)
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = """    with {:ok, bytes} <- encode_value(value), do: {:ok, digest(algorithm, bytes)}"""
new = """    with {:ok, bytes} <- encode_value(value),
         do: {:ok, digest(if(algorithm == :sha384, do: :sha256, else: algorithm), bytes)}"""
assert s.count(old) == 1, "anchor not found once: %d" % s.count(old)
s = s.replace(old, new)
io.open(p, "w", encoding="utf-8").write(s)
