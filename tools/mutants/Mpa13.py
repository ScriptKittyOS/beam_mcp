# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=test/support/public_api.ex, which passes the file to
# mutate as argv[1]. The public-API census's population, grammar and rule live there.
#
# Mpa13 -- THE NAME ALONE NAMES THE ENTRY: naming/2 drops the module (a lane's Mt1).
import sys

p = sys.argv[1]
s = open(p).read()

old = '    pattern = ~r/(?<![\\w.])#{Regex.escape("#{inspect(m)}.#{name}/#{arity}")}(?!\\d)/'
new = '    pattern = ~r/#{Regex.escape("#{name}/#{arity}")}(?!\\d)#{String.slice(inspect(m), 0, 0)}/'

if s.count(old) != 1:
    sys.exit("Mpa13: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
