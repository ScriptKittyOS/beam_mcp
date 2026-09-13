# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/declared.ex, which passes the
# file to mutate as argv[1].
#
# Mdc8 -- LET A TOOL POINT AT A MODULE OUTSIDE THE SCOPE. The edge would dangle, and Graph.new/1 would refuse the whole build for a host mistake the bound should have enumerated.
import sys

p = sys.argv[1]
s = open(p).read()

old = "             to when not is_nil(to) <- code.module_ids[module] do"
new = "             to <- Node.id({:module, server, module}) do"

if s.count(old) != 1:
    sys.exit("Mdc8: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
