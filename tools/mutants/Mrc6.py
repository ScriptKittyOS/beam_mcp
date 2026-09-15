# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/reach.ex, which passes the
# file to mutate as argv[1].
#
# Mrc6 -- LT STEP 4 SKIPPED: implicit immediate dominators are never made explicit.
import sys

p = sys.argv[1]
s = open(p).read()

old = '      if idom[w] != vertex[state.semi[w]], do: Map.put(idom, w, idom[idom[w]]), else: idom\n'
new = '      if false, do: Map.put(idom, w, idom[idom[w]]), else: idom\n'

if s.count(old) != 1:
    sys.exit("Mrc6: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
