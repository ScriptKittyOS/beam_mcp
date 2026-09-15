# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/reach.ex, which passes the
# file to mutate as argv[1].
#
# Mrc3 -- MAX_HOPS OFF BY ONE: a witness of exactly max_hops is refused.
import sys

p = sys.argv[1]
s = open(p).read()

old = '      vertices -> if length(vertices) - 1 <= max_hops, do: vertices, else: false\n'
new = '      vertices -> if length(vertices) - 1 < max_hops, do: vertices, else: false\n'

if s.count(old) != 1:
    sys.exit("Mrc3: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
