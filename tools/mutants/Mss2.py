# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/transport/http.ex, which passes the file to mutate as argv[1].
#
# Mss2 -- THE STRUCTURAL VALIDATION DROPPED on HTTP: any value passes init and fails on the first request.
import sys

p = sys.argv[1]
s = open(p).read()

old = '    defp validate_server!(server) do\n      compiled? ='
new = '    defp validate_server!(server) when is_atom(server), do: server\n\n    defp validate_server!(server) do\n      compiled? ='

if s.count(old) != 1:
    sys.exit("Mss2: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
