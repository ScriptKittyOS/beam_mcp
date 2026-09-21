# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/server.ex, which passes the file to mutate as argv[1].
#
# Mss9 -- shutdown?/1 NO LONGER OPTIONAL: every HTTP-only wrapper declaring the behaviour gets a compiler warning it cannot silence.
import sys

p = sys.argv[1]
s = open(p).read()

old = '  @optional_callbacks shutdown?: 1\n'
new = ''

if s.count(old) != 1:
    sys.exit("Mss9: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
