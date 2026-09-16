# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code a path.
# Mjs29 -- stdio: a header-line refusal returns without draining the declared body
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = """      {:error, :frame_too_large} -> drain_frame(length, :frame_too_large)"""
new = """      {:error, :frame_too_large} -> {:error, :frame_too_large}"""
assert s.count(old) == 1, "anchor not found once: %d" % s.count(old)
s = s.replace(old, new)
io.open(p, "w", encoding="utf-8").write(s)
