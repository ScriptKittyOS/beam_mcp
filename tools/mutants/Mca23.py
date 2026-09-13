# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/canonical.ex, which passes the
# file to mutate as argv[1].
#
# Mca23 -- GRAPHML WRITES ANY CHARACTER. The Char production's last clause admits what the
# ranges above it refused; a form feed or U+FFFE lands in the document. (The first draft
# emptied the node walk and orphaned its argument: a compiler kill.)
import sys

p = sys.argv[1]
s = open(p).read()

old = "  defp xml_char?(_), do: false"
new = "  defp xml_char?(_), do: true"

if s.count(old) != 1:
    sys.exit("Mca23: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
