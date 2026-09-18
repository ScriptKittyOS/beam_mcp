# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=test/support/public_api.ex, which passes the file to
# mutate as argv[1]. The public-API census's population, grammar and rule live there.
#
# Mpa18 -- THE MARKER CHECK READS since= ALONE: a removal or a deprecation dated to a number that has not shipped passes as history (a lane's Mn8).
import sys

p = sys.argv[1]
s = open(p).read()

old = '          {k, v} <- markers,\n          not this_cycle?(v),\n          do: released_marker(e, k, v, ctx.now)'
new = '          {k, v} <- markers,\n          not this_cycle?(v),\n          k == "since",\n          do: released_marker(e, k, v, ctx.now)'

if s.count(old) != 1:
    sys.exit("Mpa18: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
