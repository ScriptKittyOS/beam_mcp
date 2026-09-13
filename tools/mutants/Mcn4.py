# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/graph.ex, which passes the file to mutate as argv[1].
#
# Mcn4 -- SKIP THE SORT. Nodes and edges are kept in input order. The shuffle property must catch it; the canonical-order test must catch it.
import sys

p = sys.argv[1]
s = open(p).read()

old = "sorted = Enum.sort_by(items, identity)"
new = "sorted = items"

if s.count(old) != 1:
    sys.exit("Mcn4: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
