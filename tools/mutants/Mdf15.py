# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/diff.ex, which passes the
# file to mutate as argv[1].
#
# Mdf15 -- COMPLETENESS CONDITIONS ON THE WRONG SET: observed edges between observed nodes
# (always all of them) instead of between declared nodes -- the dual's roles, again.
import sys

p = sys.argv[1]
s = open(p).read()

old = "            MapSet.member?(declared_ids, from) and MapSet.member?(declared_ids, to)"
new = "            MapSet.member?(observed_ids, from) and MapSet.member?(observed_ids, to)"

if s.count(old) != 1:
    sys.exit("Mdf15: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
