# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code a path.
# Mjs12 -- a repeated key inside an array element is not seen: lists are handed back as decoded
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = """  defp maps(list) when is_list(list) do
    Enum.reduce_while(list, {:ok, []}, fn value, {:ok, acc} ->
      case maps(value) do
        {:ok, v} -> {:cont, {:ok, [v | acc]}}
        error -> {:halt, error}
      end
    end)"""
new = """  defp maps(list) when is_list(list) do
    Enum.reduce_while(list, {:ok, []}, fn value, {:ok, acc} ->
      case maps(value) do
        {:ok, v} -> {:cont, {:ok, [v | acc]}}
        _error -> {:cont, {:ok, [value | acc]}}
      end
    end)"""
assert s.count(old) == 1, "anchor not found once: %d" % s.count(old)
s = s.replace(old, new)
io.open(p, "w", encoding="utf-8").write(s)
