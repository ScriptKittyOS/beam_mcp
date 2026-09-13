# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/graph.ex, which passes the file
# to mutate as argv[1].
#
# Mgv1 -- SKIP THE EDGE CHECK. A host-built edge with any sign, kind or weight is held and would be hashed.
import sys

p = sys.argv[1]
s = open(p).read()

old = "         :ok <- each(edges, &Edge.check/1),"
new = "         :ok <- (fn _ -> :ok end).(edges),"

if s.count(old) != 1:
    sys.exit("Mgv1: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
