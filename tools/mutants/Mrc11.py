# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/reach.ex, which passes the
# file to mutate as argv[1].
#
# Mrc11 -- THE EDGE CAP IS EXCLUSIVE: a graph of exactly max_edges edges is refused.
import sys

p = sys.argv[1]
s = open(p).read()

old = '    if length(graph.edges) > max, do: {:error, {:cap, :max_edges, max}}, else: :ok\n'
new = '    if length(graph.edges) >= max, do: {:error, {:cap, :max_edges, max}}, else: :ok\n'

if s.count(old) != 1:
    sys.exit("Mrc11: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
