# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/canonical.ex, which passes the
# file to mutate as argv[1].
#
# Mca9 -- MERGE A DUPLICATE LABEL KEY INSTEAD OF REFUSING IT. Two keys that coincide after
# NFC collapse to the first, the way a JSON parser would on read; the graph said two.
# The first draft dropped the error arm alone and the compiler killed it (unused `id`);
# this one renames the parameter with the arm, so the kill is the test's.
import sys

p = sys.argv[1]
s = open(p).read()

edits = [
    ("  defp unique_keys(pairs, id) do", "  defp unique_keys(pairs, _id) do"),
    (
        "      [a, _] -> {:error, {:uncanonical, {:duplicate_label_key, id, elem(a, 0)}}}",
        "      [_, _] -> {:ok, Enum.uniq_by(sorted, &elem(&1, 0))}",
    ),
]

for old, new in edits:
    if s.count(old) != 1:
        sys.exit("Mca9: anchor found %d times: %s" % (s.count(old), old))
    s = s.replace(old, new, 1)

open(p, "w").write(s)
