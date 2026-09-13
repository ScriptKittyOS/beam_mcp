# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/canonical.ex, which passes the
# file to mutate as argv[1].
#
# Mca23 -- GRAPHML WRITES ANY CHARACTER. The XML 1.0 Char check answers :ok for every string; a form feed or U+FFFE lands in the document.
import sys

p = sys.argv[1]
s = open(p).read()

old = "  defp xml_chars(nodes) do\n    Enum.find_value(nodes, :ok, fn {id, _kind, _level, labels} ->"
new = "  defp xml_chars(nodes) do\n    Enum.find_value([], :ok, fn {id, _kind, _level, labels} ->"

if s.count(old) != 1:
    sys.exit("Mca23: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
