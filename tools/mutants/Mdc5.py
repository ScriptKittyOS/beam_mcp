# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/declared.ex, which passes the
# file to mutate as argv[1].
#
# Mdc5 -- KEEP SELF-LOOPS AFTER COLLAPSING TO A BOUNDARY. A call inside a group becomes an edge from the group to itself.
import sys

p = sys.argv[1]
s = open(p).read()

old = "      |> Enum.reject(fn {a, b} -> is_nil(a) or is_nil(b) or a == b end)"
new = "      |> Enum.reject(fn {a, b} -> is_nil(a) or is_nil(b) end)"

if s.count(old) != 1:
    sys.exit("Mdc5: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
