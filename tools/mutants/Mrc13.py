# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/reach.ex, which passes the
# file to mutate as argv[1].
#
# Mrc13 -- A VERTEX DOES NOT REACH ITSELF: the zero-hop clause is gone.
import sys

p = sys.argv[1]
s = open(p).read()

old = '  defp path(_dg, from, from, _opts), do: [from]\n\n'
new = '\n'

if s.count(old) != 1:
    sys.exit("Mrc13: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
