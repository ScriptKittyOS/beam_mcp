# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/declared.ex, which passes the
# file to mutate as argv[1].
#
# Mdc7 -- REPORT A DYNAMIC TARGET AS A CALLEE OUTSIDE THE SCOPE. $M_EXPR is not a module; listing it as one misfiles a dynamic site as an external dependency.
import sys

p = sys.argv[1]
s = open(p).read()

old = "        tm == :\"$M_EXPR\" ->\n          {kept, ext}"
new = "        tm == :\"$M_EXPR\" ->\n          {kept, MapSet.put(ext, tm)}"

if s.count(old) != 1:
    sys.exit("Mdc7: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
