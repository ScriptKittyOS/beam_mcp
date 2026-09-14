# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/server.ex, which passes the
# file to mutate as argv[1].
#
# Msv3 -- THE STACKTRACE GOES OUT AS THE BEAM MADE IT: argument lists in the top frame of a function_clause or a BIF error reach every handler of :exception.
import sys

p = sys.argv[1]
s = open(p).read()

old = "          Map.merge(meta, %{kind: kind, reason: reason, stacktrace: arities(stacktrace)})"
new = "          Map.merge(meta, %{kind: kind, reason: reason, stacktrace: stacktrace})"

if s.count(old) != 1:
    sys.exit("Msv3: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
