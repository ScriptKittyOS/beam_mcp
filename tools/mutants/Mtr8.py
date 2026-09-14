# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/tracer.ex, which passes the
# file to mutate as argv[1].
#
# Mtr8 -- THE TRACER DOES NOT WATCH ITS COLLECTOR. The collector's death is met as a badarg on the next traced call, not as a named exit.
import sys

p = sys.argv[1]
s = open(p).read()

old = "    _ = Process.monitor(:ets.info(collector, :owner))\n"
new = "    _ = collector\n"

if s.count(old) != 1:
    sys.exit("Mtr8: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
