# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/transport/http.ex, which passes the file to mutate as argv[1].
#
# Mss1 -- THE LITERAL RESTORED at HTTP's call site: the state is built by BeamMCP.Server whatever :server named.
import sys

p = sys.argv[1]
s = open(p).read()

old = '      case opts.server.handle_message(opts.server.new(opts.server_opts), message) do'
new = '      case opts.server.handle_message(Server.new(opts.server_opts), message) do'

if s.count(old) != 1:
    sys.exit("Mss1: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
