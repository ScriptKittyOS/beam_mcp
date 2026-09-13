# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/declared.ex, which passes the
# file to mutate as argv[1].
#
# Mdc1 -- DROP THE SCOPE FILTER ON THE CALLEE. An edge to a module outside the scope is emitted; the graph would then dangle or, worse, grow a node nobody named.
import sys

p = sys.argv[1]
s = open(p).read()

old = "        MapSet.member?(in_scope, fm) and MapSet.member?(in_scope, tm) ->\n          {[{from, to} | kept], ext}"
new = "        MapSet.member?(in_scope, fm) ->\n          {[{from, to} | kept], ext}"

if s.count(old) != 1:
    sys.exit("Mdc1: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
