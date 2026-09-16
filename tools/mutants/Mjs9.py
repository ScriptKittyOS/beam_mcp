# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code a path.
# Mjs9 -- the HTTP transport closes the connection on a nesting refusal
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = """           error(nil, -32_600, "Request body nests deeper than #{max} levels")}"""
new = """           error(nil, -32_600, "Request body nests deeper than #{max} levels")}
          |> then(fn {:refused, c, s, e} -> {:refused, Plug.Conn.put_resp_header(c, "connection", "close"), s, e} end)"""
assert s.count(old) == 1, "anchor not found once: %d" % s.count(old)
s = s.replace(old, new)
io.open(p, "w", encoding="utf-8").write(s)
