# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/diff.ex, which passes the
# file to mutate as argv[1].
#
# Mdf3 -- EVERY OBSERVED LABEL IS UNDECLARED: a label in both is classed twice.
import sys

p = sys.argv[1]
s = open(p).read()

old = "          |> Enum.reject(&Map.has_key?(d, &1))\n          |> Enum.map(&label_map/1)\n          |> sort_labels(),\n        changed_sign:"
new = "          |> Enum.map(&label_map/1)\n          |> sort_labels(),\n        changed_sign:"

if s.count(old) != 1:
    sys.exit("Mdf3: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
