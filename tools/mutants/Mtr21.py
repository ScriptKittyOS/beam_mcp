# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/tracer.ex, which passes the
# file to mutate as argv[1].
#
# Mtr21 -- A MALFORMED RUNNING TERM IS LEFT IN PLACE by stop/0 with no tracer.
import sys

p = sys.argv[1]
s = open(p).read()

old = "      :malformed ->\n        _ = :persistent_term.erase(@running)\n        :ok"
new = "      :malformed ->\n        :ok"

if s.count(old) != 1:
    sys.exit("Mtr21: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
