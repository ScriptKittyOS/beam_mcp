# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code a path.
# Mrt2 -- a zero or negative timeout is accepted
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = """    defp validate_read_timeout!(ms) when is_integer(ms) and ms > 0, do: ms"""
new = """    defp validate_read_timeout!(ms) when is_integer(ms), do: ms"""
assert s.count(old) == 1, "anchor not found once: %d" % s.count(old)
s = s.replace(old, new)
io.open(p, "w", encoding="utf-8").write(s)
