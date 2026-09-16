# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code a path.
# Mjs20 -- stdio: the over-cap legacy frame drains nothing of its body (re-anchored: an unused drain is a compiler kill)
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = """        skip_remaining_headers()
        drain_bytes(length)
        {:error, :declared_frame_too_large}"""
new = """        skip_remaining_headers()
        drain_bytes(length - length)
        {:error, :declared_frame_too_large}"""
assert s.count(old) == 1, "anchor not found once: %d" % s.count(old)
s = s.replace(old, new)
io.open(p, "w", encoding="utf-8").write(s)
