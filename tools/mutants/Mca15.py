# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/canonical.ex, which passes the
# file to mutate as argv[1].
#
# Mca15 -- THE SIDECAR SKIPS THE NODE CHECK. A graph whose ids coincide after NFC, which encode/1 refuses, gets a sidecar with two entries under one key.
import sys

p = sys.argv[1]
s = open(p).read()

old = "         {:ok, _nodes} <- canonical_nodes(graph.nodes),\n         {:ok, keyed} <-"
new = "         {:ok, keyed} <-"

if s.count(old) != 1:
    sys.exit("Mca15: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
