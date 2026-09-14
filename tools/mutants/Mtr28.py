# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/tracer.ex, which passes the
# file to mutate as argv[1].
#
# Mtr28 -- THE FLAG IS READ AFTER THE WRITE: one row lands after a stop or the deadline.
import sys

p = sys.argv[1]
s = open(p).read()

old = """      _ ->
        write.()
        counted(state)
    end
  rescue"""
new = """      _ ->
        counted(state)
    end
  rescue"""
old2 = """  defp written(%{flag: flag} = state, write) do
    case :atomics.get(flag, 1) do"""
new2 = """  defp written(%{flag: flag} = state, write) do
    write.()

    case :atomics.get(flag, 1) do"""

if s.count(old) != 1 or s.count(old2) != 1:
    sys.exit("Mtr28: anchors found %d and %d times" % (s.count(old), s.count(old2)))

open(p, "w").write(s.replace(old, new, 1).replace(old2, new2, 1))
