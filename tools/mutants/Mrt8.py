# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code a path.
# Mrt8 -- over HTTP/2 the reader is asked for a whole piece, so frames accumulate on the adapter's clock again
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = """    defp piece_length(false, _size), do: -1"""
new = """    defp piece_length(false, size), do: min(@read_piece, @max_body_bytes - size)"""
assert s.count(old) == 1, "anchor not found once: %d" % s.count(old)
s = s.replace(old, new)
io.open(p, "w", encoding="utf-8").write(s)
