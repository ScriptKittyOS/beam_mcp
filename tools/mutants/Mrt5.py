# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code a path.
# Mrt5 -- chunked bodies are admitted again (re-cut: a guard the compiler could evaluate was a compiler kill)
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = """        _chunked ->
          {:refused, conn, 411,
           error(
             nil,
             -32_600,
             "Request body must declare its length: transfer-encoding is refused"
           )}
"""
new = """        _chunked ->
          {:ok, conn}
"""
assert s.count(old) == 1, "anchor not found once: %d" % s.count(old)
s = s.replace(old, new)
io.open(p, "w", encoding="utf-8").write(s)
