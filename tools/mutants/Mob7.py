# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/observed.ex, which passes the
# file to mutate as argv[1].
#
# Mob7 -- THE ATTACH IS NOT IDEMPOTENT. A kill leaves the handler; the restart trips over it and the host's supervisor goes down -- the defect a lane found by running the collector under a supervisor.
import sys

p = sys.argv[1]
s = open(p).read()

old = "    _ = :telemetry.detach({__MODULE__, name})\n"
new = ""

if s.count(old) != 1:
    sys.exit("Mob7: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
