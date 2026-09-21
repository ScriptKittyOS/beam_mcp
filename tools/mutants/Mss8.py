# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/transport/stdio.ex, which passes the file to mutate as argv[1].
#
# Mss8 -- THE LITERAL RESTORED at stdio's first call site: the state is the core's whatever :server named.
import sys

p = sys.argv[1]
s = open(p).read()

old = '    loop(server, server.new(server_opts))'
new = '    loop(server, Server.new(server_opts))'

if s.count(old) != 1:
    sys.exit("Mss8: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
