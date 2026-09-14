# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/server.ex, which passes the
# file to mutate as argv[1].
#
# Msv7 -- AN IMPROPER ARGUMENT LIST RAISES INSIDE THE CATCH CLAUSE: the host's error is replaced and the span left open.
import sys

p = sys.argv[1]
s = open(p).read()

old = "  defp count(_, n), do: n"
new = "  defp count([], n), do: n"

if s.count(old) != 1:
    sys.exit("Msv7: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
