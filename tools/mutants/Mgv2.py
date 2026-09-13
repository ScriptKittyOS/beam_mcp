# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/graph.ex, which passes the file
# to mutate as argv[1].
#
# Mgv2 -- CORRECT AN INVALID SIGN TO :unknown INSTEAD OF REFUSING. The laundering this commit exists to forbid: a host handed a graph back with its verdict silently changed. Note the mutant writes a sign, so the sign census must also die on it.
import sys

p = sys.argv[1]
s = open(p).read()

old = "         :ok <- each(edges, &Edge.check/1),"
new = "         edges = Enum.map(edges, fn e -> if e.sign in [:allow, :deny, :hold, :unknown], do: e, else: %{e | sign: :unknown} end),\n         :ok <- each(edges, &Edge.check/1),"

if s.count(old) != 1:
    sys.exit("Mgv2: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
