# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/tracer.ex, which passes the
# file to mutate as argv[1].
#
# Mtr20 -- THE MODULE LIST IN THE RUNNING TERM IS TRUSTED UNCHECKED: a forged one raises out of stop/0 and start/1.
import sys

p = sys.argv[1]
s = open(p).read()

old = "        if atoms?(modules), do: term, else: :malformed"
new = "        if atoms?(modules), do: term, else: term"

if s.count(old) != 1:
    sys.exit("Mtr20: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
