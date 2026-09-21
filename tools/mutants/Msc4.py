# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/canonical.ex, which passes the file to mutate as argv[1].
#
# Msc4 -- THE SCHEME WRITTEN INTO THE BYTES: a member the verifier never re-derives, and every golden moves.
import sys

p = sys.argv[1]
s = open(p).read()

old = '         ~s(,"algorithm":"),'
new = '         ~s(,"scheme":"host","algorithm":"),'

if s.count(old) != 1:
    sys.exit("Msc4: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
