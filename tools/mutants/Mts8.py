# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/tracer.ex, which passes the
# file to mutate as argv[1].
#
# Mts8 -- A FAILED START LEAVES ITS SESSION TO THE COLLECTOR: init's rescue re-raises without destroying, and the error term's copy of the handle holds the session up on the caller's heap.
import sys

p = sys.argv[1]
s = open(p).read()

old = '      e ->\n        destroy(session)\n        reraise e, __STACKTRACE__'
new = '      e ->\n        reraise e, __STACKTRACE__'

if s.count(old) != 1:
    sys.exit("Mts8: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
