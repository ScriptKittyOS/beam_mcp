# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code a path.
# Mcd6 -- the connection is stopped with :normal, not :shutdown: no orderly termination runs,
# so the client sees a bare socket close, not the readable GOAWAY the row promises.
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = """        _past -> GenServer.stop(conn_pid, :shutdown, 5_000)"""
new = """        _past -> GenServer.stop(conn_pid, :normal, 5_000)"""
assert s.count(old) == 1, "anchor not found once: %d" % s.count(old)
s = s.replace(old, new)
io.open(p, "w", encoding="utf-8").write(s)
