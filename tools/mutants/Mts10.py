# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/tracer.ex, which passes the
# file to mutate as argv[1].
#
# Mts10 -- A SEND TO THE TRACER ITSELF IS AN EDGE: stop/0 and a :sys call from a traced process are written as :message edges to the tracer's name.
import sys

p = sys.argv[1]
s = open(p).read()

old = '      with false <- to == self() or to == @name,'
new = '      with false <- false,'

if s.count(old) != 1:
    sys.exit("Mts10: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
