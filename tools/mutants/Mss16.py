# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/transport/http.ex, which passes the file to mutate as argv[1].
#
# Mss16 -- THE DEFAULT RE-DERIVED AT THE CALL SITE (a lane's round-1 plant that passed both pins): the option is read from server_opts, where it never is, so the core answers whatever :server named.
import sys

p = sys.argv[1]
s = open(p).read()

old = '      case opts.server.handle_message(opts.server.new(opts.server_opts), message) do'
new = '      case opts.server.handle_message(\n             Keyword.get(opts.server_opts, :server, Server) |> then(&(&1.new(opts.server_opts))),\n             message\n           ) do'

if s.count(old) != 1:
    sys.exit("Mss16: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
