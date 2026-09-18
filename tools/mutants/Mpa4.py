# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=test/support/public_api.ex, which passes the file to
# mutate as argv[1]. The public-API census's population and grammar live there.
#
# Mpa4 -- TEST SUPPORT IS THE PACKAGE: the lib/ filter goes, and modules that ship to nobody enter the surface.
import sys

p = sys.argv[1]
s = open(p).read()

old = '        String.starts_with?(source, lib),'
new = '        String.starts_with?(source, String.slice(lib, 0, 1)),'

if s.count(old) != 1:
    sys.exit("Mpa4: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
