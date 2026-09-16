# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code a path.
# Mrt10 -- a body at the cap over HTTP/1 is refused without asking whether it is complete
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = """          {:more, piece, conn} when length == 0 and byte_size(piece) == 0 and http1 ->
            too_large(conn)"""
new = """          {:more, piece, conn} when length == 0 and byte_size(piece) == 0 and http1 ->
            read_by_deadline(conn, deadline, read_timeout, [acc, piece], size)"""
assert s.count(old) == 1, "anchor not found once: %d" % s.count(old)
s = s.replace(old, new)
io.open(p, "w", encoding="utf-8").write(s)
