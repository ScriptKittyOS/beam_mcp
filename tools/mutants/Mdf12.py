# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/diff.ex, which passes the
# file to mutate as argv[1].
#
# Mdf12 -- ONE DECLARED ENDPOINT IS ENOUGH for the completeness count: an observed edge that ran
# half outside the declared parts counts as between them.
import sys

p = sys.argv[1]
s = open(p).read()

old = "            MapSet.member?(declared_ids, from) and MapSet.member?(declared_ids, to)"
new = "            MapSet.member?(declared_ids, from) or MapSet.member?(declared_ids, to)"

if s.count(old) != 1:
    sys.exit("Mdf12: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
