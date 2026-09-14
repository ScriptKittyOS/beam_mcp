# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/observed.ex, which passes the
# file to mutate as argv[1].
#
# Mob1 -- THE COUNT NEVER MOVES. A repeated call is still one row, but its weight stays at one.
import sys

p = sys.argv[1]
s = open(p).read()

old = "    :ets.update_counter(name, key, [{2, 1}, {3, duration}], {key, 0, 0, 0})"
new = "    :ets.update_counter(name, key, [{2, 0}, {3, duration}], {key, 1, 0, 0})"

if s.count(old) != 1:
    sys.exit("Mob1: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
