# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/canonical.ex, which passes the
# file to mutate as argv[1].
#
# Mca25 -- GRAPHML KEYS NUMBERED BY BYTE ORDER, not UTF-16 code unit; above U+FFFF the two disagree and a reader files the data under the wrong name. A review lane wrote this one first and watched it survive.
import sys

p = sys.argv[1]
s = open(p).read()

old = "        |> Enum.sort(&utf16_be/2)\n"
new = "        |> Enum.sort()\n"

if s.count(old) != 1:
    sys.exit("Mca25: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
