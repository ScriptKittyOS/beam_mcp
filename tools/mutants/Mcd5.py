# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code a path.
# Mcd5 -- the connection deadline is the read deadline: held streams are closed at read_timeout, not connection_timeout
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = """      deadline = System.monotonic_time(:millisecond) + connection_timeout
      Process.put(@conn_deadline_key, deadline)"""
new = """      deadline = System.monotonic_time(:millisecond) + div(connection_timeout, 2)
      Process.put(@conn_deadline_key, deadline)"""
assert s.count(old) == 1, "anchor not found once: %d" % s.count(old)
s = s.replace(old, new)
io.open(p, "w", encoding="utf-8").write(s)
