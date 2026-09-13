# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/canonical.ex, which passes the
# file to mutate as argv[1].
#
# Mca22 -- DOT WRITES A LABEL'S ATTRIBUTE NAME RAW. A key carrying =, a space or a quote gives Graphviz a file it refuses.
import sys

p = sys.argv[1]
s = open(p).read()

old = "            | Enum.map(labels, fn {k, v} -> {dot_q(\"label_\" <> k), flat(v)} end)"
new = "            | Enum.map(labels, fn {k, v} -> {\"label_\" <> k, flat(v)} end)"

if s.count(old) != 1:
    sys.exit("Mca22: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
