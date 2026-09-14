# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/server.ex, which passes the
# file to mutate as argv[1].
#
# Msv8 -- A FRAME'S ARITY POSITION GOES OUT WHATEVER IT HOLDS: a host-built frame carrying
# the arguments there travels into the exception event.
import sys

p = sys.argv[1]
s = open(p).read()

old1 = "    for {m, f, args_or_arity, loc} <- stacktrace,\n        is_list(args_or_arity) or is_integer(args_or_arity) do"
new1 = "    for {m, f, args_or_arity, loc} <- stacktrace do"
old2 = "  defp arity(arity) when is_integer(arity), do: arity"
new2 = "  defp arity(arity), do: arity"

if s.count(old1) != 1 or s.count(old2) != 1:
    sys.exit("Msv8: anchors found %d and %d times" % (s.count(old1), s.count(old2)))

open(p, "w").write(s.replace(old1, new1, 1).replace(old2, new2, 1))
