# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/tracer.ex, which passes the
# file to mutate as argv[1].
#
# Mtr16 -- STOP CLEARS EVERY PROCESS'S FLAGS, whoever set them.
import sys

p = sys.argv[1]
s = open(p).read()

old = "    for pid <- pids,\n        :erlang.trace_info(pid, :tracer) == {:tracer, tracer},\n        do: :erlang.trace(pid, false, [:send])"
new = "    _ = {pids, tracer}\n    :erlang.trace(:all, false, [:all])"

if s.count(old) != 1:
    sys.exit("Mtr16: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
