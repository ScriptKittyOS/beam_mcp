# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/canonical.ex, which passes the
# file to mutate as argv[1].
#
# Mca20 -- LABELS READ IN THE MAP'S ORDER. Past thirty-two keys that is hash order, and which of two refused labels is named follows the runtime.
import sys

p = sys.argv[1]
s = open(p).read()

old = "    with {:ok, pairs} <- map_ok(Enum.sort(labels), fn {k, v} -> label(k, v, id) end) do"
new = "    with {:ok, pairs} <- map_ok(Map.to_list(labels), fn {k, v} -> label(k, v, id) end) do"

if s.count(old) != 1:
    sys.exit("Mca20: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
