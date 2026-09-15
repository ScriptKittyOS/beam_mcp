# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/reach.ex, which passes the
# file to mutate as argv[1].
#
# Mrc2 -- GATES ARE NOT REMOVED: the removed set is empty, so a gate node and its edges stay. (re-anchored: the first form orphaned a variable and was a compiler
# kill, which counts for nothing; every symbol stays used here)
import sys

p = sys.argv[1]
s = open(p).read()

old = '      removed = MapSet.new(removed)\n'
new = '      removed = MapSet.difference(MapSet.new(removed), MapSet.new(removed))\n'

if s.count(old) != 1:
    sys.exit("Mrc2: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
