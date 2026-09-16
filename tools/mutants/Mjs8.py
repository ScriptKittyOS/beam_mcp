# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code a path.
# Mjs8 -- the HTTP transport answers a nesting refusal as a parse error, -32700
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = """        {:error, {:nesting, _depth, max}} ->
          {:refused, conn, 400,
           error(nil, -32_600, "Request body nests deeper than #{max} levels")}
"""
new = """"""
assert s.count(old) == 1, "anchor not found once: %d" % s.count(old)
s = s.replace(old, new)
io.open(p, "w", encoding="utf-8").write(s)
