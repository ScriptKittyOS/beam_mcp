# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/transport/stdio.ex, which passes the file to mutate as argv[1].
#
# Mss14 -- stdio DOES NOT CHECK new/1 (a lane's round-1 plant).
import sys

p = sys.argv[1]
s = open(p).read()

old = '  @server_functions [new: 1, handle_message: 2, shutdown?: 1]'
new = '  @server_functions [handle_message: 2, shutdown?: 1]'

if s.count(old) != 1:
    sys.exit("Mss14: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
