# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/tracer.ex, which passes the
# file to mutate as argv[1].
#
# Mtr14 -- A NEW TRACER DOES NOT WAIT for a previous companion to finish.
import sys

p = sys.argv[1]
s = open(p).read()

old = "    await_previous_companion()\n"
new = "    _ = &await_previous_companion/0\n"

if s.count(old) != 1:
    sys.exit("Mtr14: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
