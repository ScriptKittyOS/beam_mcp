# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/server.ex, which passes the
# file to mutate as argv[1].
#
# Msv2 -- THE ARGUMENTS ENTER THE METADATA. One more key in the span's metadata carries the call's arguments to every handler.
import sys

p = sys.argv[1]
s = open(p).read()

old = "    meta = %{server_name: state.server_name, tool: tool, telemetry_span_context: make_ref()}"
new = "    meta = %{server_name: state.server_name, tool: tool, telemetry_span_context: make_ref(), args: args}"

if s.count(old) != 1:
    sys.exit("Msv2: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
