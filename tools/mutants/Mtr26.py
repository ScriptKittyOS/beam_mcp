# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/tracer.ex, which passes the
# file to mutate as argv[1].
#
# Mtr26 -- THE COMPANION TAKES THE PUBLIC TERM FOR THE RUNNING TRACER'S CLAIM: a forged one naming its own modules leaves them set.
import sys

p = sys.argv[1]
s = open(p).read()

old = """    claimed =
      case Process.whereis(@name) do
        nil ->
          []

        pid ->
          case claim(pid) do
            {_flag, modules, _pids} -> modules
            nil -> []
          end
      end
"""
new = """    claimed =
      case running_term() do
        {_flag, modules, _companion} -> modules
        _ -> []
      end
"""

if s.count(old) != 1:
    sys.exit("Mtr26: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
