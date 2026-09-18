# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/tracer.ex, which passes the
# file to mutate as argv[1].
#
# Mts4 -- THE CALL PATTERN IS SET OUTSIDE THE SESSION, under the legacy global patterns: a host's later call tracer is fed by it, and the session's destroy does not clear it.
import sys

p = sys.argv[1]
s = open(p).read()

old = '        do: :trace.function(session, {m, :_, :_}, [{:_, [], [{:message, {:caller}}]}], [:local])'
new = '        do: :erlang.trace_pattern({m, :_, :_}, [{:_, [], [{:message, {:caller}}]}], [:local])'

if s.count(old) != 1:
    sys.exit("Mts4: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
