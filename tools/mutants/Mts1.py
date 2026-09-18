# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/tracer.ex, which passes the
# file to mutate as argv[1].
#
# Mts1 -- THE HANDLE OUTLIVES ITS HOLDERS: a copy in a persistent term keeps a killed tracer's session -- and its breakpoints -- alive after both holders are gone.
import sys

p = sys.argv[1]
s = open(p).read()

old = '    Process.put(@claim, {flag, session})\n'
new = '    Process.put(@claim, {flag, session})\n    :persistent_term.put({__MODULE__, :handle}, session)\n'

if s.count(old) != 1:
    sys.exit("Mts1: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
