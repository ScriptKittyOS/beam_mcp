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

old = "    clear_patterns(modules -- claimed)\n\n    case running_term() do"
new = "    clear_patterns(modules)\n\n    case running_term() do"

if s.count(old) != 1:
    sys.exit("Mtr19: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
