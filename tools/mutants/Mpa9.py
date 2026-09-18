# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=test/support/public_api.ex, which passes the file to
# mutate as argv[1]. The public-API census's population and grammar live there.
#
# Mpa9 -- THE WRITER DOES NOT MARK WHAT LEFT: a line whose entry is gone stays unmarked, and the census reads it as a silent removal instead of asking for the record.
import sys

p = sys.argv[1]
s = open(p).read()

old = '      not MapSet.member?(present, entry) and not Map.has_key?(markers, "removed_in") ->\n        Map.put(markers, "removed_in", @unreleased)'
new = '      not MapSet.member?(present, entry) and not Map.has_key?(markers, "removed_in") ->\n        markers'

if s.count(old) != 1:
    sys.exit("Mpa9: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
