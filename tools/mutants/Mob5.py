# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/observed.ex, which passes the
# file to mutate as argv[1].
#
# Mob5 -- THE EDGE'S PROVENANCE IS DECLARED. The observed graph claims to be the tree's.
import sys

p = sys.argv[1]
s = open(p).read()

old = "            provenance: :observed,"
new = "            provenance: :declared,"

if s.count(old) != 1:
    sys.exit("Mob5: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
