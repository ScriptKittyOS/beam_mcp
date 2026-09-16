# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code a path.
# Mjs4 -- a closing bracket does not count back down: siblings add up
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = """  defp nesting(<<?], rest::binary>>, depth, max), do: nesting(rest, depth - 1, max)"""
new = """  defp nesting(<<?], rest::binary>>, depth, max), do: nesting(rest, depth, max)"""
assert s.count(old) == 1, "anchor not found once: %d" % s.count(old)
s = s.replace(old, new)
io.open(p, "w", encoding="utf-8").write(s)
