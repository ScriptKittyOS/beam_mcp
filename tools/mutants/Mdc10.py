# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/declared.ex, which passes the
# file to mutate as argv[1].
#
# Mdc10 -- DROP A CALL WITH AN UNGROUPED END. Not an edge, and not enumerated either: the compiled code showed it and the bound loses it. The split result is still bound so the kill is a test's and not the compiler's.
import sys

p = sys.argv[1]
s = open(p).read()

for old, new in [
    [
        "    {grouped_calls, ungrouped_calls} =",
        "    {grouped_calls, _dropped} ="
    ],
    [
        "{nodes, edges, ids, ungrouped, Enum.sort(ungrouped_calls), [source]}",
        "{nodes, edges, ids, ungrouped, [], [source]}"
    ]
]:
    if s.count(old) != 1:
        sys.exit("Mdc10: anchor found %d times: %r" % (s.count(old), old[:40]))
    s = s.replace(old, new, 1)

open(p, "w").write(s)
