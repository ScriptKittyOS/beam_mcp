# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/server.ex, which passes the
# file to mutate as argv[1].
#
# Msv5 -- A FILE OF ANY LIST SHAPE IS KEPT: a host-built frame's file value travels whatever it holds.
import sys

p = sys.argv[1]
s = open(p).read()

old = "    if :io_lib.char_list(file),"
new = "    if is_list(file),"

if s.count(old) != 1:
    sys.exit("Msv5: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
