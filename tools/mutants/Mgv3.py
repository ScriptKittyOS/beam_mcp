# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/graph.ex, which passes the file
# to mutate as argv[1].
#
# Mgv3 -- SKIP THE NODE CHECK. A host-built node with any kind or a non-string id is held.
import sys

p = sys.argv[1]
s = open(p).read()

old = "         :ok <- each(nodes, &Node.check/1),"
new = "         :ok <- (fn _ -> :ok end).(nodes),"

if s.count(old) != 1:
    sys.exit("Mgv3: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
