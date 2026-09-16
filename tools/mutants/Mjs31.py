# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code a path.
# Mjs31 -- stdio: a size refusal is a parse error again
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = """  defp refusal(:frame_too_large),
    do: error(nil, -32_600, "Request line exceeds #{@max_line_bytes} bytes")"""
new = """  defp refusal(:frame_too_large),
    do: error(nil, -32_700, "Request line exceeds #{@max_line_bytes} bytes")"""
assert s.count(old) == 1, "anchor not found once: %d" % s.count(old)
s = s.replace(old, new)
io.open(p, "w", encoding="utf-8").write(s)
