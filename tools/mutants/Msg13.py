# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/signer.ex, which passes the file to mutate as argv[1].
#
# Msg13 -- THE RETURN WIDENED: | {:ok, binary(), map()} beside the two shapes (round 1 lane (b) M1: passed the whole suite under the substring match).
import sys

p = sys.argv[1]
s = open(p).read()

old = '              {:ok, binary()} | {:error, term()}\nend\n'
new = '              {:ok, binary()} | {:error, term()} | {:ok, binary(), map()}\nend\n'

if s.count(old) != 1:
    sys.exit("Msg13: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
