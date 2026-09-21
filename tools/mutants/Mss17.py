# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/transport/http.ex, which passes the file to mutate as argv[1].
#
# Mss17 -- THE CORE UNDER AN if (a lane's round-2 plant): the if's clauses carry generated: true and the bare literal inherits the mark, so an atom-site pin that skipped generated sites passed it.
import sys

p = sys.argv[1]
s = open(p).read()

old = '      case opts.server.handle_message(opts.server.new(opts.server_opts), message) do'
new = '      case opts.server.handle_message(\n             (if opts.server, do: Server) |> then(& &1.new(opts.server_opts)),\n             message\n           ) do'

if s.count(old) != 1:
    sys.exit("Mss17: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
