# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/diff.ex, which passes the
# file to mutate as argv[1].
#
# Mdf7 -- NODES IN BOTH COUNTS THE UNION.
import sys

p = sys.argv[1]
s = open(p).read()

old = "        nodes_in_both: MapSet.size(MapSet.intersection(declared_ids, observed_ids))"
new = "        nodes_in_both: MapSet.size(MapSet.union(declared_ids, observed_ids))"

if s.count(old) != 1:
    sys.exit("Mdf7: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
