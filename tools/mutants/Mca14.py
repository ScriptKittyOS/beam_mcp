# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/canonical.ex, which passes the
# file to mutate as argv[1].
#
# Mca14 -- THE SIDECAR ZIPS THE GRAPH'S ORDER AGAINST THE CANONICAL ORDER. The defect a review lane found: weights pair with the wrong edge wherever NFC reorders.
import sys

p = sys.argv[1]
s = open(p).read()

old = "           map_ok(graph.edges, &with({:ok, {key, _}} <- canonical_edge(&1), do: {:ok, {&1, key}})) do"
new = "           (with {:ok, sorted} <- canonical_edges(graph.edges), do: {:ok, Enum.zip(graph.edges, Enum.map(sorted, &elem(&1, 0)))}) do"

if s.count(old) != 1:
    sys.exit("Mca14: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
