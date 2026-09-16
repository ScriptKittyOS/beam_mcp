# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code a path.
# Mjs1 -- the bound is never enforced: the walk runs and its answer is ignored (re-anchored: an unused walk is a compiler kill)
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = """    case nesting(body, 0, @max_depth) do"""
new = """    _ = nesting(body, 0, @max_depth)

    case :ok do"""
assert s.count(old) == 1, "anchor not found once: %d" % s.count(old)
s = s.replace(old, new)
io.open(p, "w", encoding="utf-8").write(s)
