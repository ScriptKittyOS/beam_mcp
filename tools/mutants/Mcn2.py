# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/edge.ex, which passes the file to mutate as argv[1].
#
# Mcn2 -- ACCEPT :sign AS A CONSTRUCTOR KEY. Still defaults to :unknown, but a caller could now hand one in. The refusal test and the census (the atom :sign appears in a code line) must both catch it.
import sys

p = sys.argv[1]
s = open(p).read()

old = "@keys [:from, :to, :kind, :provenance, :weight]"
new = "@keys [:from, :to, :kind, :provenance, :weight, :sign]"

if s.count(old) != 1:
    sys.exit("Mcn2: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
