# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=test/support/public_api.ex, which passes the file to
# mutate as argv[1]. The public-API census's population, grammar and rule live there.
#
# Mpa15 -- THE CENSUS IS SWITCHED OFF: no marker is ever this cycle's, so additions, deprecations, removals and leftovers are never checked (a lane's Mt4).
import sys

p = sys.argv[1]
s = open(p).read()

old = '  defp this_cycle?(v), do: v == @unreleased'
new = '  defp this_cycle?(v), do: v == @unreleased and false'

if s.count(old) != 1:
    sys.exit("Mpa15: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
