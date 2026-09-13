# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/graph.ex, which passes the file to mutate as argv[1].
#
# Mcn8 -- FORGET THE DANGLING CHECK. An edge may point at a node the graph does not hold. The dangling-edge refusal must catch it.
#
# TWO REPLACEMENTS, BECAUSE ONE WOULD BE A COMPILER KILL. The first version removed the
# check and left its helper or attribute unused; --warnings-as-errors rejected the build
# before a test ran (CONVENTIONS.md, "the compiler kill"). The mutation is completed by also
# removing what it orphans.
import sys

p = sys.argv[1]
s = open(p).read()

for old, new in [
    [
        "         :ok <- endpoints_present(nodes, edges) do",
        "         :ok <- (fn _, _ -> :ok end).(nodes, edges) do"
    ],
    [
        "  defp endpoints_present(nodes, edges) do\n    ids = MapSet.new(nodes, & &1.id)\n\n    edges\n    |> Enum.flat_map(&[&1.from, &1.to])\n    |> Enum.find(&(not MapSet.member?(ids, &1)))\n    |> case do\n      nil -> :ok\n      id -> {:error, {:dangling_edge, id}}\n    end\n  end\n",
        ""
    ]
]:
    if s.count(old) != 1:
        sys.exit("Mcn8: anchor found %d times: %r" % (s.count(old), old[:40]))
    s = s.replace(old, new, 1)

open(p, "w").write(s)
