# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/canonical.ex, which passes the
# file to mutate as argv[1].
#
# Mca6 -- HASH WITH SHA-1. The document says SHA-256; the golden hex and the worked example say what that means.
import sys

p = sys.argv[1]
s = open(p).read()

old = "    with {:ok, bytes} <- encode(graph), do: {:ok, :crypto.hash(:sha256, bytes)}"
new = "    with {:ok, bytes} <- encode(graph), do: {:ok, :crypto.hash(:sha, bytes) <> <<0::96>>}"

if s.count(old) != 1:
    sys.exit("Mca6: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
