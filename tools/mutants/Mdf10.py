# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/diff.ex, which passes the
# file to mutate as argv[1].
#
# Mdf10 -- A GRAPH WITH THE OTHER SIDE'S PROVENANCE IS ADMITTED: two edges collapse into one label.
import sys

p = sys.argv[1]
s = open(p).read()

old = "    case Enum.find(edges, &(&1.provenance != side)) do"
new = "    case Enum.find(edges, &(&1.provenance != side and &1.provenance == side)) do"

if s.count(old) != 1:
    sys.exit("Mdf10: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
