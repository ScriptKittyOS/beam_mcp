# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code a path.
# Mha10 -- a second spelling admitted: the string sha384 maps to the atom (lane a's surviving plant c)
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = """    case Keyword.get(opts, :algorithm, @default_algorithm) do
      algorithm when algorithm in @algorithms ->
        algorithm"""
new = """    case Keyword.get(opts, :algorithm, @default_algorithm) do
      "sha384" ->
        :sha384

      algorithm when algorithm in @algorithms ->
        algorithm"""
assert s.count(old) == 1, "anchor not found once: %d" % s.count(old)
s = s.replace(old, new)
io.open(p, "w", encoding="utf-8").write(s)
