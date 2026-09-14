# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/tracer.ex, which passes the
# file to mutate as argv[1].
#
# Mtr24 -- A NAMED PID'S SEND FLAG IS CLEARED WHOEVER SET IT: a host's re-trace is wiped, and a dead named process is a badarg in terminate.
import sys

p = sys.argv[1]
s = open(p).read()

old = "        :erlang.trace_info(pid, :tracer) == {:tracer, tracer},"
new = "        is_pid(pid) or is_pid(tracer),"

if s.count(old) != 1:
    sys.exit("Mtr24: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
