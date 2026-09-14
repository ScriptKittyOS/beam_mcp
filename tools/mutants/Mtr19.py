# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/tracer.ex, which passes the
# file to mutate as argv[1].
#
# Mtr19 -- A LATE COMPANION CLEARS EVERYTHING IT NAMED, the new tracer's claim included.
import sys

p = sys.argv[1]
s = open(p).read()

old = "      {_other, claimed, _} ->\n        clear_patterns(modules -- claimed)"
new = "      {_other, claimed, _} ->\n        clear_patterns(modules ++ claimed -- claimed)"

if s.count(old) != 1:
    sys.exit("Mtr19: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
