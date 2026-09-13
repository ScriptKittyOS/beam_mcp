# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/declared.ex, which passes the
# file to mutate as argv[1].
#
# Mdc5 -- KEEP SELF-LOOPS AFTER COLLAPSING TO A BOUNDARY. A call inside a group becomes an edge from the group to itself. Two anchors: the boundary level has two rejects now (grouped-ness, then self-loops); only the self-loop one is removed, and only at this level (the :module level keeps its own).
import sys

p = sys.argv[1]
s = open(p).read()

for old, new in [
    [
        "      grouped_calls\n      |> Enum.map(fn {{fm, _, _}, {tm, _, _}} -> {ids[fm], ids[tm]} end)\n      |> Enum.reject(fn {a, b} -> a == b end)",
        "      grouped_calls\n      |> Enum.map(fn {{fm, _, _}, {tm, _, _}} -> {ids[fm], ids[tm]} end)"
    ]
]:
    if s.count(old) != 1:
        sys.exit("Mdc5: anchor found %d times: %r" % (s.count(old), old[:40]))
    s = s.replace(old, new, 1)

open(p, "w").write(s)
