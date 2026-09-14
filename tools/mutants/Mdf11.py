# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/diff.ex, which passes the
# file to mutate as argv[1].
#
# Mdf11 -- A GRAPH WITH NO CANONICAL BYTES GETS A DIFF WITH CANONICAL BYTES: the encoder's refusals are ignored.
import sys

p = sys.argv[1]
s = open(p).read()

old = "      {:error, {:uncanonical, {:invalid_graph, reason}}} -> {:error, reason}\n      other -> other"
new = "      {:error, {:uncanonical, {:invalid_graph, reason}}} -> {:error, reason}\n      _other -> :ok"

if s.count(old) != 1:
    sys.exit("Mdf11: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
