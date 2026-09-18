# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=test/support/public_api.ex, which passes the file to
# mutate as argv[1]. The public-API census's population, grammar and rule live there.
#
# Mpa19 -- MACROS ARE NOT A KIND: a documented defmacro is off the surface (a lane's Mn9).
import sys

p = sys.argv[1]
s = open(p).read()

old = '  @kinds [:function, :macro, :callback, :type]'
new = '  @kinds [:function, :callback, :type]'

if s.count(old) != 1:
    sys.exit("Mpa19: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
