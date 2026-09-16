# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code a path.
# Mjs16 -- stdio: a non-object line is silence again
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = """      {:ok, other} ->
        write_message(
          error(nil, -32_600, "Expected a JSON object, got #{BeamMCP.JSON.type_of(other)}")
        )

        loop(state)"""
new = """      {:ok, other} ->
        _ = BeamMCP.JSON.type_of(other)
        loop(state)"""
assert s.count(old) == 1, "anchor not found once: %d" % s.count(old)
s = s.replace(old, new)
io.open(p, "w", encoding="utf-8").write(s)
