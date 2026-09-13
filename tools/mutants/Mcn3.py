# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/node.ex, which passes the file to mutate as argv[1].
#
# Mcn3 -- DROP THE KIND VALIDATION. Any atom becomes a kind. The named-refusal test must catch it.
#
# TWO REPLACEMENTS, BECAUSE ONE WOULD BE A COMPILER KILL. The first version removed the
# check and left its helper or attribute unused; --warnings-as-errors rejected the build
# before a test ran (CONVENTIONS.md, "the compiler kill"). The mutation is completed by also
# removing what it orphans.
import sys

p = sys.argv[1]
s = open(p).read()

for old, new in [
    [
        "{:ok, kind} <- member(opts, :kind, @kinds),",
        "{:ok, kind} <- {:ok, Keyword.fetch!(opts, :kind)},"
    ],
    [
        "  @kinds [:server, :tool, :resource, :prompt, :process, :module]\n",
        ""
    ]
]:
    if s.count(old) != 1:
        sys.exit("Mcn3: anchor found %d times: %r" % (s.count(old), old[:40]))
    s = s.replace(old, new, 1)

open(p, "w").write(s)
