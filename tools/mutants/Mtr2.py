# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/tracer.ex, which passes the
# file to mutate as argv[1].
#
# Mtr2 -- PATTERNS ARE LEFT BEHIND on stop: the modules stay traced after the tracer is gone.
import sys

p = sys.argv[1]
s = open(p).read()

old = "    for m <- state.modules, do: :erlang.trace_pattern({m, :_, :_}, false, [:local])"
new = "    for m <- state.modules, do: m"

if s.count(old) != 1:
    sys.exit("Mtr2: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
