# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=test/support/public_api.ex, which passes the file to
# mutate as argv[1]. The public-API census's population, grammar and rule live there.
#
# Mpa12 -- THE WRITER NEVER MARKS A DEPRECATION (a lane's Mb3).
import sys

p = sys.argv[1]
s = open(p).read()

old = '        Map.put(markers, "deprecated_since", @unreleased)'
new = '        markers'

if s.count(old) != 1:
    sys.exit("Mpa12: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
