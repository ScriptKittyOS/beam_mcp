# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/transport/http.ex, which passes the file to mutate as argv[1].
#
# Mss15 -- THE CORE PIPED INTO A CALL (a lane's round-1 plant that passed the text and xref pins): Server |> then(& &1.new(x)) compiles to a variable-module call with the atom at a second site.
import sys

p = sys.argv[1]
s = open(p).read()

old = '      case opts.server.handle_message(opts.server.new(opts.server_opts), message) do'
new = '      case opts.server.handle_message(Server |> then(& &1.new(opts.server_opts)), message) do'

if s.count(old) != 1:
    sys.exit("Mss15: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
