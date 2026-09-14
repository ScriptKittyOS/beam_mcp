# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/diff.ex, which passes the
# file to mutate as argv[1].
#
# Mdf2 -- EVERY DECLARED LABEL IS IN BOTH: dead authority is classed as declared_and_observed.
import sys

p = sys.argv[1]
s = open(p).read()

old = "      in_both = Map.keys(d) |> Enum.filter(&Map.has_key?(o, &1))"
new = "      in_both = Map.keys(d)"

if s.count(old) != 1:
    sys.exit("Mdf2: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
