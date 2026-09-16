# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code a path.
# Mrt1 -- the option is validated but not passed: read_body runs on the adapter's default again
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = """      case read_body(conn, length: @max_body_bytes, read_timeout: read_timeout) do"""
new = """      _ = read_timeout

      case read_body(conn, length: @max_body_bytes) do"""
assert s.count(old) == 1, "anchor not found once: %d" % s.count(old)
s = s.replace(old, new)
io.open(p, "w", encoding="utf-8").write(s)
