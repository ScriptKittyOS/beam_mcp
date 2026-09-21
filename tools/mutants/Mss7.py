# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/transport/stdio.ex, which passes the file to mutate as argv[1].
#
# Mss7 -- :server NOT POPPED on stdio: it rides into the module's new/1.
import sys

p = sys.argv[1]
s = open(p).read()

old = '    {server, server_opts} = Keyword.pop(opts, :server, Server)'
new = '    {server, server_opts} = {Keyword.get(opts, :server, Server), opts}'

if s.count(old) != 1:
    sys.exit("Mss7: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
