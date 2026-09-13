# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/canonical.ex, which passes the
# file to mutate as argv[1].
#
# Mca24 -- GRAPHML WRITES A TAB LITERALLY. A parser folds it to a space inside an attribute value; two ids differing by whitespace kind read back as one node.
import sys

p = sys.argv[1]
s = open(p).read()

old = "    \"\\t\" => \"&#9;\",\n"
new = "    \"\\t\" => \"\\t\",\n"

if s.count(old) != 1:
    sys.exit("Mca24: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
