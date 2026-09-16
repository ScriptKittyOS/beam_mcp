# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code a path.
# Mjs22 -- stdio: the over-cap legacy frame is refused as a line, not a frame
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = """  defp refusal(:declared_frame_too_large),
    do: error(nil, -32_700, "Parse error: frame exceeds #{@max_body_bytes} bytes")"""
new = """  defp refusal(:declared_frame_too_large),
    do: error(nil, -32_700, "Parse error: line exceeds #{@max_body_bytes} bytes")"""
assert s.count(old) == 1, "anchor not found once: %d" % s.count(old)
s = s.replace(old, new)
io.open(p, "w", encoding="utf-8").write(s)
