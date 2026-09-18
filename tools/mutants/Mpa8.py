# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=test/support/public_api.ex, which passes the file to
# mutate as argv[1]. The public-API census's population and grammar live there.
#
# Mpa8 -- DEFAULT ARGUMENTS ARE NOT PART OF THE ENTRY: dropping a default (a callable arity gone) is no change.
import sys

p = sys.argv[1]
s = open(p).read()

old = '        do: {{m, kind, name, arity, meta[:defaults] || 0}, meta}'
new = '        do: {{m, kind, name, arity, 0}, meta}'

if s.count(old) != 1:
    sys.exit("Mpa8: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
