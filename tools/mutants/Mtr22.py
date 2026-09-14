# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/tracer.ex, which passes the
# file to mutate as argv[1].
#
# Mtr22 -- THE PUT ON A FORGED FLAG RAISES OUT OF stop/0 after the patterns are cleared, with the tracer left alive.
import sys

p = sys.argv[1]
s = open(p).read()

old = "  rescue\n    ArgumentError -> :ok"
new = "  rescue\n    ArithmeticError -> :ok"

if s.count(old) != 1:
    sys.exit("Mtr22: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
