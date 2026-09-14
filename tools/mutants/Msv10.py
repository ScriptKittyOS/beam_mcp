# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/server.ex, which passes the
# file to mutate as argv[1].
#
# Msv10 -- AN UNKNOWN OPTION IS HELD SILENTLY: a host's typo is never seen.
import sys

p = sys.argv[1]
s = open(p).read()

old = "      :error ->\n        raise ArgumentError,\n              \"BeamMCP.Server.new/1 does not take #{inspect(key)}; the options are \" <>\n                Enum.map_join(Keyword.keys(@options), \", \", &inspect/1)"
new = "      :error ->\n        :ok"
if s.count(old) != 1:
    sys.exit("Msv10: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
