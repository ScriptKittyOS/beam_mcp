# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/tracer.ex, which passes the
# file to mutate as argv[1].
#
# Mts7 -- A DURATION BEYOND THE TIMER RANGE IS ACCEPTED: the companion dies on its first instruction and the tracer leaves companion_gone at once.
import sys

p = sys.argv[1]
s = open(p).read()

old = '      n when n <= @max_duration_ms -> :ok\n'
new = '      n when n <= @max_duration_ms * 2 -> :ok\n'

if s.count(old) != 1:
    sys.exit("Mts7: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
