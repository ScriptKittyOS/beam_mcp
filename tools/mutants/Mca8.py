# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/canonical.ex, which passes the
# file to mutate as argv[1].
#
# Mca8 -- WRITE A CONTROL CHARACTER LITERALLY. RFC 8785 says \\u00xx; the escaping test carries U+0001.
import sys

p = sys.argv[1]
s = open(p).read()

old = "  defp escape_char(c) when c < 0x20,"
new = "  defp escape_char(c) when c < 0x08,"

if s.count(old) != 1:
    sys.exit("Mca8: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
