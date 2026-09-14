# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/server.ex, which passes the
# file to mutate as argv[1].
#
# Msv6 -- A LINE OF ANY NUMERIC SHAPE IS KEPT: a float line a host built travels.
import sys

p = sys.argv[1]
s = open(p).read()

old = "  defp location([{:line, line} | rest], acc) when is_integer(line),"
new = "  defp location([{:line, line} | rest], acc) when is_number(line),"

if s.count(old) != 1:
    sys.exit("Msv6: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
