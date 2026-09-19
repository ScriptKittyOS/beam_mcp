# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/canonical.ex, which passes the file to mutate as argv[1].
#
# Msg11 -- A NON-BINARY SIGNATURE IS ACCEPTED: the guard admits any term.
import sys

p = sys.argv[1]
s = open(p).read()

old = '        {:ok, sig} when is_binary(sig) ->'
new = '        {:ok, sig} when is_binary(sig) or is_atom(sig) ->'

if s.count(old) != 1:
    sys.exit("Msg11: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
