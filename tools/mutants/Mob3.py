# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/observed.ex, which passes the
# file to mutate as argv[1].
#
# Mob3 -- A COLLECTOR THAT IS NOT RUNNING IS AN EMPTY GRAPH, not a named refusal: 'nothing
# ran' where 'nothing was watching' was true. (The refusal is kept reachable on one
# impossible name so the type checker does not kill the mutant for us.)
import sys

p = sys.argv[1]
s = open(p).read()

old = "      :undefined -> {:error, :not_started}"
new = "      :undefined -> if name == :no_such_name, do: {:error, :not_started}, else: {:ok, []}"

if s.count(old) != 1:
    sys.exit("Mob3: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
