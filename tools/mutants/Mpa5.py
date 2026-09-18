# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=test/support/public_api.ex, which passes the file to
# mutate as argv[1]. The public-API census's population and grammar live there.
#
# Mpa5 -- THE GRAMMAR ACCEPTS ANY MARKER: a misspelt or invented marker is kept as if it meant something.
import sys

p = sys.argv[1]
s = open(p).read()

old = '          [k, v] when k in ["since", "deprecated_since", "removed_in"] -> {k, v}'
new = '          [k, v] -> {k, v}'

if s.count(old) != 1:
    sys.exit("Mpa5: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
