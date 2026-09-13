# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/node.ex, which passes the file
# to mutate as argv[1].
#
# Mcn12 -- LET ANY KIND CARRY A BOUNDARY IDENTITY. A tool at the :boundary level with a boundary identity would be accepted; only a module-kind node groups modules.
import sys

p = sys.argv[1]
s = open(p).read()

old = "    elem(identity, 0) == kind or (elem(identity, 0) == :boundary and kind == :module)"
new = "    elem(identity, 0) == kind or elem(identity, 0) == :boundary"

if s.count(old) != 1:
    sys.exit("Mcn12: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
