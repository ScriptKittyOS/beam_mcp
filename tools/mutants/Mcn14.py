# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/node.ex, which passes the
# file to mutate as argv[1].
#
# Mcn14 -- A STRUCT IS ADMITTED AS THE LABELS MAP, by new/1 and by check/1; its __struct__ and fields reach the canonical bytes.
import sys

p = sys.argv[1]
s = open(p).read()

edits = [
    ("      {:labels, &(is_map(&1) and not is_struct(&1))}", "      {:labels, &is_map/1}"),
    ("      labels when is_map(labels) and not is_struct(labels) -> {:ok, labels}", "      labels when is_map(labels) -> {:ok, labels}"),
]

for old, new in edits:
    if s.count(old) != 1:
        sys.exit("Mcn14: anchor found %d times: %s" % (s.count(old), old))
    s = s.replace(old, new, 1)

open(p, "w").write(s)
