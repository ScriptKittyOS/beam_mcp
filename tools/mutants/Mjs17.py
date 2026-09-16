# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code a path.
# Mjs17 -- stdio: the parse error carries the inspected reason again
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = """  defp refusal(_decode_error), do: error(nil, -32_700, "Parse error: body is not valid JSON")"""
new = """  defp refusal(decode_error),
    do:
      error(nil, -32_700, "Parse error: body is not valid JSON")
      |> put_in(["error", "data"], inspect(decode_error))"""
assert s.count(old) == 1, "anchor not found once: %d" % s.count(old)
s = s.replace(old, new)
io.open(p, "w", encoding="utf-8").write(s)
