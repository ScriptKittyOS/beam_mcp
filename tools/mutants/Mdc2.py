# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/declared.ex, which passes the
# file to mutate as argv[1].
#
# Mdc2 -- SUMMARISE THE UNRESOLVED CALLS TO A COUNT. The bound exists to enumerate; a number is the thing the issue forbids.
import sys

p = sys.argv[1]
s = open(p).read()

old = "         unresolved: Enum.sort(unresolved),"
new = "         unresolved: length(unresolved),"

if s.count(old) != 1:
    sys.exit("Mdc2: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
