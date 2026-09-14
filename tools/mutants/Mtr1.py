# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/tracer.ex, which passes the
# file to mutate as argv[1].
#
# Mtr1 -- THE MESSAGE LIMIT IS NEVER REACHED. seen + 1 >= max becomes false forever: an unbounded mode.
import sys

p = sys.argv[1]
s = open(p).read()

old = "    if seen + queued >= max do"
new = "    if seen + queued >= max and max < 0 do"

if s.count(old) != 1:
    sys.exit("Mtr1: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
