# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/tracer.ex, which passes the
# file to mutate as argv[1].
#
# Mts5 -- stop/0 DESTROYS WITHOUT RAISING THE FLAG: what was queued before the destroy is drained and written.
import sys

p = sys.argv[1]
s = open(p).read()

old = '          {flag, session} ->\n            :atomics.put(flag, 1, @stop)\n            destroy(session)'
new = '          {flag, session} ->\n            _ = flag\n            destroy(session)'

if s.count(old) != 1:
    sys.exit("Mts5: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
