# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code a path.
# Mcd1 -- the watchdog is never armed: the connection is never closed
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = """      if get_http_protocol(conn) == :"HTTP/2" and is_integer(connection_timeout) do"""
new = """      if get_http_protocol(conn) == :"HTTP/9" and is_integer(connection_timeout) do"""
assert s.count(old) == 1, "anchor not found once: %d" % s.count(old)
s = s.replace(old, new)
io.open(p, "w", encoding="utf-8").write(s)
