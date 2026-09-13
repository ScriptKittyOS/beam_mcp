# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/canonical.ex, which passes the
# file to mutate as argv[1].
#
# Mca13 -- NESTED OBJECT SKIPS THE DUPLICATE-KEY CHECK. A nested label object sorts its keys but never refuses two that coincide.
import sys

p = sys.argv[1]
s = open(p).read()

old = "         {:ok, sorted} <- unique_keys(pairs, id) do\n      {:ok, {:object, sorted}}"
new = "         sorted = Enum.sort_by(pairs, &elem(&1, 0), &utf16_le/2) do\n      {:ok, {:object, sorted}}"

if s.count(old) != 1:
    sys.exit("Mca13: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
