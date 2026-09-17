# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code a path.
# Mcd6 -- the connection is found by any link, not the shutdown handler: the wrong process is stopped
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = """            {mod, _, _} -> function_exported?(mod, :handle_shutdown, 2)"""
new = """            {_mod, _, _} -> true"""
assert s.count(old) == 1, "anchor not found once: %d" % s.count(old)
s = s.replace(old, new)
io.open(p, "w", encoding="utf-8").write(s)
