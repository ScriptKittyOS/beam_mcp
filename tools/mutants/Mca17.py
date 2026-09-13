# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/canonical.ex, which passes the
# file to mutate as argv[1].
#
# Mca17 -- ESCAPE DEL TOO. U+007F is written as \\u007f, the way some JSON writers do; the layout says literal.
import sys

p = sys.argv[1]
s = open(p).read()

old = "  defp escape_char(c) when c < 0x20,"
new = "  defp escape_char(c) when c < 0x20 or c == 0x7F,"

if s.count(old) != 1:
    sys.exit("Mca17: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
