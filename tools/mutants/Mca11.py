# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/canonical.ex, which passes the
# file to mutate as argv[1].
#
# Mca11 -- ATOM VALUE NOT NORMALISED. An atom label value is written as spelled.
import sys

p = sys.argv[1]
s = open(p).read()

old = "  defp value(v, _id, _k) when is_atom(v), do: {:ok, nfc(Atom.to_string(v))}"
new = "  defp value(v, _id, _k) when is_atom(v), do: {:ok, Atom.to_string(v)}"

if s.count(old) != 1:
    sys.exit("Mca11: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
