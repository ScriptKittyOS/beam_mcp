# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/tracer.ex, which passes the
# file to mutate as argv[1].
#
# Mtr4 -- THE ARITY FLAG IS DROPPED: trace messages carry the arguments -- the payload -- to the tracer.
import sys

p = sys.argv[1]
s = open(p).read()

old = "    if modules != [], do: :erlang.trace(:all, true, [:call, :arity, {:tracer, self()}])"
new = "    if modules != [], do: :erlang.trace(:all, true, [:call, {:tracer, self()}])"

if s.count(old) != 1:
    sys.exit("Mtr4: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
