# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/transport/http.ex, which passes the file to mutate as argv[1].
#
# Mss3 -- THE new/1 CHECK AT A WRONG ARITY on HTTP: a correct wrapper is refused.
import sys

p = sys.argv[1]
s = open(p).read()

old = '    @server_functions [new: 1, handle_message: 2]'
new = '    @server_functions [new: 2, handle_message: 2]'

if s.count(old) != 1:
    sys.exit("Mss3: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
