# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code a path.
# Mjs26 -- the citation reader reads only the nearest attribute line of the run (re-anchored: an unused attribute is a compiler kill)
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = """    |> Enum.take_while(&Regex.match?(@attribute_or_blank, &1))"""
new = """    |> Enum.take_while(&Regex.match?(@attribute_or_blank, &1))
    |> Enum.take(1)"""
assert s.count(old) == 1, "anchor not found once: %d" % s.count(old)
s = s.replace(old, new)
io.open(p, "w", encoding="utf-8").write(s)
