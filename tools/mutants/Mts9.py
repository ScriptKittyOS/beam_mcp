# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/tracer.ex, which passes the
# file to mutate as argv[1].
#
# Mts9 -- A PLAIN REFERENCE IN A CLAIM'S FLAG SLOT RAISES OUT OF stop/0: the rescue around :atomics.put/3 is gone.
import sys

p = sys.argv[1]
s = open(p).read()

old = '    :atomics.put(flag, 1, @stop)\n    destroy(session)\n  rescue\n    ArgumentError -> false\n  end'
new = '    :atomics.put(flag, 1, @stop)\n    destroy(session)\n  end'

if s.count(old) != 1:
    sys.exit("Mts9: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
