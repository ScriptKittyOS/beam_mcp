# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/graph.ex, which passes the file
# to mutate as argv[1].
#
# Mgv2b -- THE MINIMAL LAUNDER. Correct a refused sign to :unknown using only the struct
# default's spelling, so the line carries no atom the census would name. Review showed the
# census's `sign: :unknown` permitted form let exactly this through; the form is now the
# defstruct spelling, and this mutant is what proves the narrowing did work.
import sys

p = sys.argv[1]
s = open(p).read()

old = "         :ok <- each(edges, &Edge.check/1),"
new = "         edges = Enum.map(edges, fn e -> if Edge.check(e) == :ok, do: e, else: %{e | sign: :unknown} end),\n         :ok <- each(edges, &Edge.check/1),"

if s.count(old) != 1:
    sys.exit("Mgv2b: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
