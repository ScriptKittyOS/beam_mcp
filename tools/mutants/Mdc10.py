# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/declared.ex, which passes the
# file to mutate as argv[1].
#
# Mdc10 -- DROP A CALL WITH AN UNGROUPED END. Not an edge, and not enumerated either: the compiled code showed it and the bound loses it.
import sys

p = sys.argv[1]
s = open(p).read()

old = "        Map.has_key?(ids, fm) and Map.has_key?(ids, tm)\n      end)"
new = "        Map.has_key?(ids, fm) and Map.has_key?(ids, tm)\n      end)\n\n    ungrouped_calls = []"

if s.count(old) != 1:
    sys.exit("Mdc10: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
