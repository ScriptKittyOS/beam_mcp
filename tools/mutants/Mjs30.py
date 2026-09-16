# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code a path.
# Mjs30 -- stdio: the line accumulates as a list of one-byte binaries again
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = """  defp read_line_bounded(acc) do
    case IO.binread(:stdio, 1) do
      :eof when acc == <<>> -> :eof
      :eof -> {:ok_line, acc}
      {:error, reason} -> {:error, reason}
      "\\n" -> {:ok_line, acc}
      byte -> read_line_bounded(acc <> byte)
    end
  end"""
new = """  defp read_line_bounded(acc) when is_binary(acc), do: read_line_bounded(for <<b <- acc>>, do: <<b>>)

  defp read_line_bounded(acc) do
    case IO.binread(:stdio, 1) do
      :eof when acc == [] -> :eof
      :eof -> {:ok_line, acc |> Enum.reverse() |> IO.iodata_to_binary()}
      {:error, reason} -> {:error, reason}
      "\\n" -> {:ok_line, acc |> Enum.reverse() |> IO.iodata_to_binary()}
      byte -> read_line_bounded([byte | acc])
    end
  end"""
assert s.count(old) == 1, "anchor not found once: %d" % s.count(old)
s = s.replace(old, new)
io.open(p, "w", encoding="utf-8").write(s)
