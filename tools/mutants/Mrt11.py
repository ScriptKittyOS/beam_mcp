# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code a path.
# Mrt11 -- over HTTP/2 the reader is asked for zero, which an empty frame does not exceed: the round-1 cut
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = """    defp piece_length(false, _size), do: -1"""
new = """    defp piece_length(false, _size), do: 0"""
assert s.count(old) == 1, "anchor not found once: %d" % s.count(old)
s = s.replace(old, new)
io.open(p, "w", encoding="utf-8").write(s)
