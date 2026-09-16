# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code a path.
# Mjs2 -- off by one: a body nested exactly at the bound is refused
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = """  defp nesting(<<?[, _::binary>>, depth, max) when depth >= max, do: {:too_deep, depth + 1}
  defp nesting(<<?{, _::binary>>, depth, max) when depth >= max, do: {:too_deep, depth + 1}"""
new = """  defp nesting(<<?[, _::binary>>, depth, max) when depth >= max - 1, do: {:too_deep, depth + 1}
  defp nesting(<<?{, _::binary>>, depth, max) when depth >= max - 1, do: {:too_deep, depth + 1}"""
assert s.count(old) == 1, "anchor not found once: %d" % s.count(old)
s = s.replace(old, new)
io.open(p, "w", encoding="utf-8").write(s)
