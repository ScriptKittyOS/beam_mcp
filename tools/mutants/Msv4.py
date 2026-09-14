# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/server.ex, which passes the
# file to mutate as argv[1].
#
# Msv4 -- A FRAME'S LOCATION KEYWORDS GO OUT WHOLE: a host's error_info travels in the exception event.
import sys

p = sys.argv[1]
s = open(p).read()

old = "       Keyword.take(loc, [:file, :line])}"
new = "       loc}"

if s.count(old) != 1:
    sys.exit("Msv4: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
