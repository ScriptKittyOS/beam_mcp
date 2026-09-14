# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/tracer.ex, which passes the
# file to mutate as argv[1].
#
# Mtr15 -- THE TRACER DOES NOT WATCH ITS COMPANION: the companion's death leaves a tracer with no deadline and no janitor.
import sys

p = sys.argv[1]
s = open(p).read()

old = "    _ = Process.monitor(companion)\n"
new = ""

if s.count(old) != 1:
    sys.exit("Mtr15: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
