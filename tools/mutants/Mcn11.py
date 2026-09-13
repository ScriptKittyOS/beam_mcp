# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/node.ex, which passes the file
# to mutate as argv[1].
#
# Mcn11 -- DROP THE SOURCE FROM THE BOUNDARY ID. An application named :foo and a boundary module Foo would no longer be told apart by source; the decision this commit records exists to refuse exactly that.
import sys

p = sys.argv[1]
s = open(p).read()

old = "    do: [server, \"boundary\", \"application\", Atom.to_string(app)]"
new = "    do: [server, \"boundary\", Atom.to_string(app)]"

if s.count(old) != 1:
    sys.exit("Mcn11: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
