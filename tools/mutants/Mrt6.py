# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code a path.
# Mrt6 -- the adapter's 408 is reraised instead of answered here
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = """            if Plug.Exception.status(exception) == 408,
              do: timed_out(conn, read_timeout),
              else: reraise(exception, __STACKTRACE__)"""
new = """            _ = timed_out(conn, read_timeout)
            reraise(exception, __STACKTRACE__)"""
assert s.count(old) == 1, "anchor not found once: %d" % s.count(old)
s = s.replace(old, new)
io.open(p, "w", encoding="utf-8").write(s)
