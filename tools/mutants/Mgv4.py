# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/edge.ex, which passes the file
# to mutate as argv[1].
#
# Mgv4 -- DROP THE SIGN FROM THE EDGE CHECK. Every other field is still checked; a sign outside
# the vocabulary passes into the graph. Two replacements: the first version left @signs unused
# and --warnings-as-errors rejected the build before a test ran (a compiler kill, which counts
# for nothing); the attribute goes with its one use.
import sys

p = sys.argv[1]
s = open(p).read()

for old, new in [
    [
        "      {:weight, &(is_nil(&1) or (is_number(&1) and &1 >= 0))},\n      {:sign, &(&1 in @signs)}",
        "      {:weight, &(is_nil(&1) or (is_number(&1) and &1 >= 0))}"
    ],
    [
        "  @signs [:allow, :deny, :hold, :unknown]\n",
        ""
    ]
]:
    if s.count(old) != 1:
        sys.exit("Mgv4: anchor found %d times: %r" % (s.count(old), old[:40]))
    s = s.replace(old, new, 1)

open(p, "w").write(s)
