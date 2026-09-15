# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/reach.ex, which passes the
# file to mutate as argv[1].
#
# Mrc12 -- REACHABLE-FROM-ENTRIES INVERTED: a reachable target is reported unreachable.
import sys

p = sys.argv[1]
s = open(p).read()

old = '      if path(dg, @root, target, %{max_hops: :infinity}) == false,\n'
new = '      if path(dg, @root, target, %{max_hops: :infinity}) != false,\n'

if s.count(old) != 1:
    sys.exit("Mrc12: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
