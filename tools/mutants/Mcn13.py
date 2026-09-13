# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/node.ex, which passes the file
# to mutate as argv[1].
#
# Mcn13 -- FORGET THAT A BOUNDARY IDENTITY MEANS THE :boundary LEVEL. A boundary identity at level :module would be accepted, and the level would no longer say what the id says.
import sys

p = sys.argv[1]
s = open(p).read()

old = "  defp level_consistent?({:boundary, _, _, _}, level), do: level == :boundary"
new = "  defp level_consistent?({:boundary, _, _, _}, _level), do: true"

if s.count(old) != 1:
    sys.exit("Mcn13: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
