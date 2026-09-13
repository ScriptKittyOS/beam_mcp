# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/declared.ex, which passes the
# file to mutate as argv[1].
#
# Mdc4 -- DROP AN UNREADABLE CATALOG ENTRY SILENTLY. The one thing the reader must never do.
import sys

p = sys.argv[1]
s = open(p).read()

old = "        {nodes, [{field, entry} | bad]}"
new = "        {nodes, bad}"

if s.count(old) != 1:
    sys.exit("Mdc4: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
