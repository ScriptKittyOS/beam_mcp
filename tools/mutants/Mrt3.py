# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code a path.
# Mrt3 -- the stated default is not the one in force
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = """    @read_timeout_default 15_000"""
new = """    @read_timeout_default 1_500"""
assert s.count(old) == 1, "anchor not found once: %d" % s.count(old)
s = s.replace(old, new)
io.open(p, "w", encoding="utf-8").write(s)
