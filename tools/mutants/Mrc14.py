# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/reach.ex, which passes the
# file to mutate as argv[1].
#
# Mrc14 -- UNKNOWN OPTIONS ARE ACCEPTED SILENTLY.
import sys

p = sys.argv[1]
s = open(p).read()

old = '      key -> {:error, {:unknown_option, key}}\n'
new = '      _key -> :ok\n'

if s.count(old) != 1:
    sys.exit("Mrc14: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
