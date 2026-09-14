# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/server.ex, which passes the
# file to mutate as argv[1].
#
# Msv1 -- THE OUTCOME IS ALWAYS :ok. An error the dispatch returned is reported to consumers as success.
import sys

p = sys.argv[1]
s = open(p).read()

old = "  defp outcome({:ok, _}), do: :ok\n  defp outcome(_), do: :error"
new = "  defp outcome({:ok, _}), do: :ok\n  defp outcome(_), do: :ok"

if s.count(old) != 1:
    sys.exit("Msv1: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
