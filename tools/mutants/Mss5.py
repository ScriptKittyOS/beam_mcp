# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/transport/stdio.ex, which passes the file to mutate as argv[1].
#
# Mss5 -- THE LITERAL RESTORED at stdio's third call site: the loop asks BeamMCP.Server whether a wrapper's state has ended.
import sys

p = sys.argv[1]
s = open(p).read()

old = '        if server.shutdown?(next_state) do'
new = '        if Server.shutdown?(next_state) do'

if s.count(old) != 1:
    sys.exit("Mss5: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
