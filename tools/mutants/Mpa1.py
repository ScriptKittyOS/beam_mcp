# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=test/support/public_api.ex, which passes the file to
# mutate as argv[1]. The public-API census's population and grammar live there.
#
# Mpa1 -- TWO MINORS ARE ENOUGH: the three-minor wait becomes two.
import sys

p = sys.argv[1]
s = open(p).read()

old = '      do: now.minor - since.minor >= 3,'
new = '      do: now.minor - since.minor >= 2,'

if s.count(old) != 1:
    sys.exit("Mpa1: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
