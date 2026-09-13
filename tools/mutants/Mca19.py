# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/canonical.ex, which passes the
# file to mutate as argv[1].
#
# Mca19 -- THE LITERAL GRAPH IS NOT CHECKED. checked/1 answers :ok without asking
# Graph.check/1; a dangling invalid-UTF-8 endpoint or a struct as labels reaches the writer
# again. The first draft kept a dead {:error, _} arm and the compiler killed it (a clause
# that never matches is a warning); the whole function is replaced now.
import sys

p = sys.argv[1]
s = open(p).read()

old = "  defp checked(graph) do\n    case Graph.check(graph) do\n      :ok -> :ok\n      {:error, reason} -> {:error, {:uncanonical, {:invalid_graph, reason}}}\n    end\n  end"
new = "  defp checked(_graph), do: :ok"

if s.count(old) != 1:
    sys.exit("Mca19: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
