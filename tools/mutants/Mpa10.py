# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=test/support/public_api.ex, which passes the file to
# mutate as argv[1]. The public-API census's population, grammar and rule live there.
#
# Mpa10 -- NOTHING IS DEPRECATED: deprecated/1 answers [] whatever the chunks say (a lane's Mb1, a survivor on the tree before the fixture pins).
import sys

p = sys.argv[1]
s = open(p).read()

old = '    for {entry, meta} <- listed(modules), is_binary(meta[:deprecated]), do: entry'
new = '    for {entry, meta} <- listed(modules), is_binary(meta[:deprecated]) and false, do: entry'

if s.count(old) != 1:
    sys.exit("Mpa10: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
