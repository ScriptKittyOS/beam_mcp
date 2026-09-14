# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/observed.ex, which passes the
# file to mutate as argv[1].
#
# Mob6 -- ONLY :stop IS ATTACHED. A call that raised is not an attempt; the edge is lost.
import sys

p = sys.argv[1]
s = open(p).read()

old = "  @events [[:beam_mcp, :dispatch, :stop], [:beam_mcp, :dispatch, :exception]]"
new = "  @events [[:beam_mcp, :dispatch, :stop]]"

if s.count(old) != 1:
    sys.exit("Mob6: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
