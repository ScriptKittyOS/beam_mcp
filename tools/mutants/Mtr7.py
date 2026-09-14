# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/tracer.ex, which passes the
# file to mutate as argv[1].
#
# Mtr7 -- A LIMIT OF ZERO IS ACCEPTED: n > 0 becomes n >= 0, and max_messages: 0 starts a tracer that stops on its first message -- or never.
import sys

p = sys.argv[1]
s = open(p).read()

old = "      n when is_integer(n) and n > 0 -> :ok"
new = "      n when is_integer(n) and n >= 0 -> :ok"

if s.count(old) != 1:
    sys.exit("Mtr7: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
