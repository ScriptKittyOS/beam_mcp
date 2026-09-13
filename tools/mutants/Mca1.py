# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/canonical.ex, which passes the
# file to mutate as argv[1].
#
# Mca1 -- SKIP THE NODE SORT. Nodes keep the order the graph handed them (already sorted by Graph.new, so the shuffle property must reach the encoder through a graph that was not) -- the canonical order is the encoder`s own, or it is nobody`s.
import sys

p = sys.argv[1]
s = open(p).read()

old = "      sorted = Enum.sort_by(list, &elem(&1, 0))"
new = "      sorted = list"

if s.count(old) != 1:
    sys.exit("Mca1: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
