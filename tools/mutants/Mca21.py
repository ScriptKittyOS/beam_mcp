# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/canonical.ex, which passes the
# file to mutate as argv[1].
#
# Mca21 -- NODES SORTED BY UTF-16 CODE UNIT, the label-key order, instead of by code point. Above U+FFFF the two orders differ; a JavaScript verifier's default sort would agree with the mutant.
import sys

p = sys.argv[1]
s = open(p).read()

old = "      sorted = Enum.sort_by(list, &elem(&1, 0))\n"
new = "      sorted = Enum.sort_by(list, &elem(&1, 0), &utf16_le/2)\n"

if s.count(old) != 1:
    sys.exit("Mca21: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
