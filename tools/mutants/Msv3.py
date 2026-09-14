# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/server.ex, which passes the
# file to mutate as argv[1].
#
# Msv3 -- THE STACKTRACE GOES OUT AS THE BEAM MADE IT: argument lists in the top frame of a
# function_clause or a BIF error reach every handler of :exception. (Mutated inside
# arities/1; the first draft bypassed the function and the compiler killed it as unused.)
import sys

p = sys.argv[1]
s = open(p).read()

old = "      {m, f, if(is_list(args_or_arity), do: length(args_or_arity), else: args_or_arity), loc}"
new = "      {m, f, args_or_arity, loc}"

if s.count(old) != 1:
    sys.exit("Msv3: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
