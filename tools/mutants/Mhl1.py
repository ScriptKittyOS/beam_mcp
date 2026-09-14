# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/transport/http.ex, which passes the
# file to mutate as argv[1].
#
# Mhl1 -- THE FAULT LOG CARRIES THE HOST'S STACKTRACE UNTOUCHED: a caller's arguments in the top frame reach the log.
import sys

p = sys.argv[1]
s = open(p).read()

old = "      Logger.error(Exception.format(kind, reason, BeamMCP.Stacktrace.arities(stacktrace)))"
new = "      Logger.error(Exception.format(kind, reason, stacktrace))"

if s.count(old) != 1:
    sys.exit("Mhl1: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
