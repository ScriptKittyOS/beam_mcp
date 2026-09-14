# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/tracer.ex, which passes the
# file to mutate as argv[1].
#
# Mtr11 -- THE COMPANION DOES NOT CLEAR ON THE TRACER'S EXIT: a kill leaves the patterns set with no tracer.
import sys

p = sys.argv[1]
s = open(p).read()

old = "        {:DOWN, ^ref, :process, ^tracer, _reason} ->\n          clear_patterns(modules)\n          :persistent_term.erase(@running)\n      after"
new = "        {:DOWN, ^ref, :process, ^tracer, _reason} ->\n          :persistent_term.erase(@running)\n      after"

if s.count(old) != 1:
    sys.exit("Mtr11: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
