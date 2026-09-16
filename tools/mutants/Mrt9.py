# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code a path.
# Mrt9 -- connection: close is put on HTTP/2 responses again
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = """      case get_http_protocol(conn) do
        :"HTTP/2" -> conn
        _ -> put_resp_header(conn, "connection", "close")
      end"""
new = """      case get_http_protocol(conn) do
        :"HTTP/9" -> conn
        _ -> put_resp_header(conn, "connection", "close")
      end"""
assert s.count(old) == 1, "anchor not found once: %d" % s.count(old)
s = s.replace(old, new)
io.open(p, "w", encoding="utf-8").write(s)
