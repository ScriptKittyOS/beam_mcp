# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/tracer.ex, which passes the
# file to mutate as argv[1].
#
# Mtr6 -- AN UNREGISTERED PROCESS IS WRITTEN UNDER ITS PID: the registered-name lookup falls back to inspect(pid).
import sys

p = sys.argv[1]
s = open(p).read()

old = "      {:registered_name, name} when is_atom(name) and name != [] -> {:ok, name}\n      _ -> :error"
new = "      {:registered_name, name} when is_atom(name) and name != [] -> {:ok, name}\n      _ -> {:ok, String.to_atom(inspect(pid))}"

if s.count(old) != 1:
    sys.exit("Mtr6: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
