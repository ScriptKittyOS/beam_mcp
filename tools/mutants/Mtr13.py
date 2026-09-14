# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/tracer.ex, which passes the
# file to mutate as argv[1].
#
# Mtr13 -- THE COMPANION ERASES ANY RUNNING TERM, its own or the next tracer's.
import sys

p = sys.argv[1]
s = open(p).read()

old = "      {^flag, _, _} -> :persistent_term.erase(@running)\n      _ -> :ok"
new = "      {_, _, _} -> :persistent_term.erase(@running)\n      _ -> :ok"

if s.count(old) != 1:
    sys.exit("Mtr13: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
