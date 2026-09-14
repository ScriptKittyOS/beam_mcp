# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/observed.ex, which passes the
# file to mutate as argv[1].
#
# Mob8 -- A FOREIGN ROW IS BUILT, NOT REFUSED: well_formed/1 answers :ok for any row.
import sys

p = sys.argv[1]
s = open(p).read()

old = "  defp well_formed(rows) do\n    Enum.find_value(rows, :ok, fn"
new = "  defp well_formed(rows) do\n    Enum.find_value([] ++ [] || rows, :ok, fn"

if s.count(old) != 1:
    sys.exit("Mob8: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
