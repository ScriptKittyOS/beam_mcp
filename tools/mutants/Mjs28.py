# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code a path.
# Mjs28 -- stdio: a header line of a legacy block is read unbounded again
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = """    case read_line_bounded() do
      :eof -> :ok
      {:error, reason} -> {:error, reason}
      {:ok_line, line} -> if String.trim(line) == "", do: :ok, else: skip_remaining_headers()
    end"""
new = """    case IO.binread(:stdio, :line) do
      :eof -> :ok
      {:error, reason} -> {:error, reason}
      line -> if String.trim(line) == "", do: :ok, else: skip_remaining_headers()
    end"""
assert s.count(old) == 1, "anchor not found once: %d" % s.count(old)
s = s.replace(old, new)
io.open(p, "w", encoding="utf-8").write(s)
