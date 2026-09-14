# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/diff.ex, which passes the
# file to mutate as argv[1].
#
# Mdf5 -- THE CLASS LISTS ARE IN THE OTHER ORDER: the page's order, and the worked example, no longer hold.
import sys

p = sys.argv[1]
s = open(p).read()

old = "    Enum.sort_by(labels, &{utf16(&1.from), utf16(&1.to), utf16(Atom.to_string(&1.kind))})"
new = "    Enum.sort_by(labels, &{utf16(&1.from), utf16(&1.to), utf16(Atom.to_string(&1.kind))}, :desc)"

if s.count(old) != 1:
    sys.exit("Mdf5: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
