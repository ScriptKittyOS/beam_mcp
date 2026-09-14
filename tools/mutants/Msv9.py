# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/server.ex, which passes the
# file to mutate as argv[1].
#
# Msv9 -- A NON-STRING server_name IS HELD AGAIN: it raises inside the connectome's id derivation at snapshot time, not at new/1.
import sys

p = sys.argv[1]
s = open(p).read()

old = "  defp valid?(:server_name, value), do: is_binary(value)"
new = "  defp valid?(:server_name, value), do: is_binary(value) or is_atom(value)"

if s.count(old) != 1:
    sys.exit("Msv9: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
