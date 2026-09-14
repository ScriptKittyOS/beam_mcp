# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/tracer.ex, which passes the
# file to mutate as argv[1].
#
# Mtr23 -- THE COMPANION CLEARS NOTHING WHEN NO TRACER RUNS: a kill leaves its patterns set.
import sys

p = sys.argv[1]
s = open(p).read()

old = "      case Process.whereis(@name) do\n        nil ->\n          []"
new = "      case Process.whereis(@name) do\n        nil ->\n          modules"

if s.count(old) != 1:
    sys.exit("Mtr23: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
