# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/tracer.ex, which passes the
# file to mutate as argv[1].
#
# Mts2 -- NEW PROCESSES ARE NOT TRACED: the call flag goes on the processes alive at start only.
import sys

p = sys.argv[1]
s = open(p).read()

old = '    if modules != [], do: :trace.process(session, :all, true, [:call, :arity])'
new = '    if modules != [], do: :trace.process(session, :existing, true, [:call, :arity])'

if s.count(old) != 1:
    sys.exit("Mts2: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
