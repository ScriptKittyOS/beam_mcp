# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/diff.ex, which passes the
# file to mutate as argv[1].
#
# Mdf1 -- A SIGN ON ONE SIDE ONLY IS A CHANGE: unknown against allow lands in changed_sign.
import sys

p = sys.argv[1]
s = open(p).read()

old = "    do: declared != :unknown and observed != :unknown and declared != observed"
new = "    do: declared != observed"

if s.count(old) != 1:
    sys.exit("Mdf1: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
