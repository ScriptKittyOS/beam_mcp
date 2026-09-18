# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=test/support/public_api.ex, which passes the file to
# mutate as argv[1]. The public-API census's population and grammar live there.
#
# Mpa2 -- A 1.x MINOR MAY REMOVE: the next-major rule becomes same-major-or-later.
import sys

p = sys.argv[1]
s = open(p).read()

old = '      else: now.major > since.major'
new = '      else: now.major >= since.major'

if s.count(old) != 1:
    sys.exit("Mpa2: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
