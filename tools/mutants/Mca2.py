# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/canonical.ex, which passes the
# file to mutate as argv[1].
#
# Mca2 -- SKIP THE EDGE SORT.
import sys

p = sys.argv[1]
s = open(p).read()

old = "    {:ok, Enum.sort_by(list, &elem(&1, 0))}"
new = "    {:ok, list}"

if s.count(old) != 1:
    sys.exit("Mca2: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
