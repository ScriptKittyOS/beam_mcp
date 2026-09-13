# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/declared.ex, which passes the
# file to mutate as argv[1].
#
# Mdc4 -- DROP AN UNREADABLE CATALOG ENTRY SILENTLY. The one thing the reader must never do. The discarded pair is still bound, so the kill is a test`s and not the compiler`s.
import sys

p = sys.argv[1]
s = open(p).read()

old = "        {nodes, [{field, entry} | bad]}"
new = "        _ = {field, entry}\n        {nodes, bad}"

if s.count(old) != 1:
    sys.exit("Mdc4: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
