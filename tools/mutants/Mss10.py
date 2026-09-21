# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/server.ex, which passes the file to mutate as argv[1].
#
# Mss10 -- A FOURTH CALLBACK on the behaviour: the seam widens without a census noticing.
import sys

p = sys.argv[1]
s = open(p).read()

old = '  @callback shutdown?(state :: term()) :: boolean()\n'
new = '  @callback shutdown?(state :: term()) :: boolean()\n\n  @doc false\n  @callback authorize(state :: term(), message :: map()) :: boolean()\n  @optional_callbacks authorize: 2\n'

if s.count(old) != 1:
    sys.exit("Mss10: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
