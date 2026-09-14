# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/tracer.ex, which passes the
# file to mutate as argv[1].
#
# Mtr9 -- A SEND TO A DEAD PROCESS IS NOT COUNTED: the shape falls to the ignore clause and max_messages does not bound it.
import sys

p = sys.argv[1]
s = open(p).read()

old = "  def handle_info({:trace, _from, :send_to_non_existing_process, _message, _to}, state),\n    do: counted(state)\n"
new = "  def handle_info({:trace, _from, :send_to_non_existing_process, _message, _to}, state),\n    do: {:noreply, state}\n"

if s.count(old) != 1:
    sys.exit("Mtr9: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
