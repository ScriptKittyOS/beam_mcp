# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/reach.ex, which passes the
# file to mutate as argv[1].
#
# Mrc15 -- THE DFS IS A BFS: successors go to the back of the work list, so the numbering is no depth-first preorder.
import sys

p = sys.argv[1]
s = open(p).read()

old = '      walk(dg, next ++ rest, MapSet.put(seen, v), [v | order], parent)\n'
new = '      walk(dg, rest ++ next, MapSet.put(seen, v), [v | order], parent)\n'

if s.count(old) != 1:
    sys.exit("Mrc15: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
