# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/transport/http.ex, which passes the file to mutate as argv[1].
#
# Mss11 -- HTTP CHECKS new/1 ALONE (a lane's round-1 plant, survived before the one-missing-function fixtures): a module without handle_message/2 passes init and fails on the first request.
import sys

p = sys.argv[1]
s = open(p).read()

old = '    @server_functions [new: 1, handle_message: 2]'
new = '    @server_functions [new: 1]'

if s.count(old) != 1:
    sys.exit("Mss11: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
