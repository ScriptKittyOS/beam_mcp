# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/tracer.ex, which passes the
# file to mutate as argv[1].
#
# Mtr17 -- A WRITE INTO A TABLE THAT IS GONE IS A CRASH, not the named way out.
import sys

p = sys.argv[1]
s = open(p).read()

old = "  rescue\n    ArgumentError -> {:stop, {:shutdown, :collector_gone}, state}"
new = "  rescue\n    ArgumentError -> {:stop, {:shutdown, :collector_gone_twice}, state}"

if s.count(old) != 1:
    sys.exit("Mtr17: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
