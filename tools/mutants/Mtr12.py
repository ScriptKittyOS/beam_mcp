# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/tracer.ex, which passes the
# file to mutate as argv[1].
#
# Mtr12 -- THE DEADLINE CLEARS NOTHING FROM OUTSIDE: the companion only sends the message, which queues behind the trace messages.
import sys

p = sys.argv[1]
s = open(p).read()

old = "          clear(modules, pids, tracer)\n          :atomics.put(flag, 1, @deadline)\n          send(tracer, :max_duration)"
new = "          _ = {modules, pids}\n          :atomics.put(flag, 1, @deadline)\n          send(tracer, :max_duration)"

if s.count(old) != 1:
    sys.exit("Mtr12: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
