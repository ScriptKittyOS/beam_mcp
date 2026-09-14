# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/tracer.ex, which passes the
# file to mutate as argv[1].
#
# Mtr13 -- THE WILDCARD IS ADMITTED in modules:.
import sys

p = sys.argv[1]
s = open(p).read()

old = "        if Enum.all?(list, &(is_atom(&1) and &1 != :_ and Code.ensure_loaded?(&1))),"
new = "        if Enum.all?(list, &(is_atom(&1) and Code.ensure_loaded?(&1))),"

if s.count(old) != 1:
    sys.exit("Mtr13: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
