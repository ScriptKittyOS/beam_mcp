# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/canonical.ex, which passes the
# file to mutate as argv[1].
#
# Mca7 -- SORT OBJECT KEYS BY UTF-8 BYTE INSTEAD OF UTF-16 CODE UNIT. Equal for BMP keys; the emoji-versus-fullwidth fixture tells them apart.
import sys

p = sys.argv[1]
s = open(p).read()

old = "  defp utf16(s), do: :unicode.characters_to_binary(s, :utf8, {:utf16, :big})"
new = "  defp utf16(s), do: s"

if s.count(old) != 1:
    sys.exit("Mca7: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
