# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/tracer.ex, which passes the
# file to mutate as argv[1].
#
# Mts3 -- THE SEND FLAG IS SET OUTSIDE THE SESSION, under the legacy tracer: a host's legacy trace(false, [:all]) wipes it, and session_destroy/1 does not reach it.
import sys

p = sys.argv[1]
s = open(p).read()

old = '    for name <- processes, do: :trace.process(session, Process.whereis(name), true, [:send])'
new = '    for name <- processes, do: :erlang.trace(Process.whereis(name), true, [:send, {:tracer, self()}])'

if s.count(old) != 1:
    sys.exit("Mts3: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
