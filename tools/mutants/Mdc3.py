# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/declared.ex, which passes the
# file to mutate as argv[1].
#
# Mdc3 -- INVENT A NODE FOR A MODULE WITH NO BEAM. A name with nothing behind it becomes a node; the bound loses the module it should have listed.
import sys

p = sys.argv[1]
s = open(p).read()

old = "        :no_beam -> {added, [m | no_beam], no_dbg}"
new = "        :no_beam -> {[m | added], no_beam, no_dbg}"

if s.count(old) != 1:
    sys.exit("Mdc3: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
