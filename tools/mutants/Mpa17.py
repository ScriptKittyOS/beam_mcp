# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=test/support/public_api.ex, which passes the file to
# mutate as argv[1]. The public-API census's population, grammar and rule live there.
#
# Mpa17 -- THE RELEASE STEP LETS A REMOVAL SHIP IN A PATCH.
import sys

p = sys.argv[1]
s = open(p).read()

old = '        parsed.patch != 0 ->'
new = '        parsed.patch != 0 and parsed.patch < 0 ->'

if s.count(old) != 1:
    sys.exit("Mpa17: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
