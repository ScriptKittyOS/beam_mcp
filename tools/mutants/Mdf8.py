# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/diff.ex, which passes the
# file to mutate as argv[1].
#
# Mdf8 -- A WINDOW WITH NO CANONICAL BYTES IS ACCEPTED at run/2 and fails at encode/1.
import sys

p = sys.argv[1]
s = open(p).read()

old = "        with {:ok, _} <- Canonical.encode_value(window, :window), do: {:ok, window}"
new = "        {:ok, window}"

if s.count(old) != 1:
    sys.exit("Mdf8: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
