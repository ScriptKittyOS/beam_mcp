# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/reach.ex, which passes the
# file to mutate as argv[1].
#
# Mrc1 -- THE KIND FILTER IS DROPPED: every edge enters the digraph whatever kinds: says. (re-anchored: the first form orphaned a variable and was a compiler
# kill, which counts for nothing; every symbol stays used here)
import sys

p = sys.argv[1]
s = open(p).read()

old = '          MapSet.member?(kinds, e.kind),\n'
new = '          MapSet.member?(kinds, e.kind) or e.kind in Edge.kinds(),\n'

if s.count(old) != 1:
    sys.exit("Mrc1: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
