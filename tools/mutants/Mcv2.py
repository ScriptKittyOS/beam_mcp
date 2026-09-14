# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/canonical.ex, which passes the
# file to mutate as argv[1].
#
# Mcv2 -- Canonical.check/1 SKIPS THE NODES: ids that coincide after NFC pass the check the encoder would refuse.
import sys

p = sys.argv[1]
s = open(p).read()

old = "         {:ok, _nodes} <- canonical_nodes(graph.nodes),\n         {:ok, _edges} <- canonical_edges(graph.edges) do\n      :ok"
new = "         {:ok, _edges} <- canonical_edges(graph.edges) do\n      :ok"

if s.count(old) != 1:
    sys.exit("Mcv2: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
