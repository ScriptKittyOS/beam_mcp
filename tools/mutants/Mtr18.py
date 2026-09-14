# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/tracer.ex, which passes the
# file to mutate as argv[1].
#
# Mtr18 -- A START DOES NOT CLEAR A STALE TERM: the double-kill window's patterns stay until a tracer naming them exits.
import sys

p = sys.argv[1]
s = open(p).read()

old = "    await_previous_companion()\n    stop_stale()\n"
new = "    await_previous_companion()\n"

if s.count(old) != 1:
    sys.exit("Mtr18: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
