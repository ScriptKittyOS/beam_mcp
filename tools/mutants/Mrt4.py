# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code a path.
# Mrt4 -- each read gets the whole timeout instead of what remains: two reads, two deadlines again
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = """          read_body(conn, length: length, read_length: @read_piece, read_timeout: remaining)"""
new = """          read_body(conn, length: length, read_length: @read_piece, read_timeout: read_timeout + remaining - remaining)"""
assert s.count(old) == 1, "anchor not found once: %d" % s.count(old)
s = s.replace(old, new)
io.open(p, "w", encoding="utf-8").write(s)
