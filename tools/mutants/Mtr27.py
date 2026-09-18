# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/tracer.ex, which passes the
# file to mutate as argv[1].
#
# Mtr27 -- A CLAIM'S FLAG IS TRUSTED UNCHECKED: a squatter's crafted flag makes stop/0 raise out of :atomics.put/3.
import sys

p = sys.argv[1]
s = open(p).read()

old = '         true <- is_reference(flag) do'
new = '         true <- is_reference(flag) or true do'

if s.count(old) != 1:
    sys.exit("Mtr27: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
