# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/reach.ex, which passes the
# file to mutate as argv[1].
#
# Mrc5 -- THE WITNESS IGNORES kinds: any edge between the two vertices is taken. (re-anchored: the first form orphaned a variable and was a compiler
# kill, which counts for nothing; every symbol stays used here)
import sys

p = sys.argv[1]
s = open(p).read()

old = '        Enum.find(graph.edges, &(&1.from == a and &1.to == b and &1.kind in kinds))\n'
new = '        Enum.find(graph.edges, &(&1.from == a and &1.to == b and (&1.kind in kinds or &1.kind in Edge.kinds())))\n'

if s.count(old) != 1:
    sys.exit("Mrc5: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
