# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/observed.ex, which passes the
# file to mutate as argv[1].
#
# Mob2 -- THE MAX IS NEVER REWRITTEN. The latency summary's max stays at the first sample -- zero on a warm table.
import sys

p = sys.argv[1]
s = open(p).read()

old = "    if :ets.lookup_element(name, key, 4) < duration do"
new = "    if false and :ets.lookup_element(name, key, 4) < duration do"

if s.count(old) != 1:
    sys.exit("Mob2: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
