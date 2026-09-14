# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Evaluates a Livebook's Elixir cells in order, outside Livebook, the way Livebook would:
# one binding threaded through every cell, modules defined in one cell visible to the
# next, `__DIR__` the notebook's directory. The first cell is the notebook's own
# `Mix.install`, which is why this runs under `elixir` and not `mix run` -- Mix.install
# refuses to run inside a Mix project, and that is the point: the notebook must stand on
# what it installs.
#
#     elixir tools/livebook_eval.exs livebooks/connectome.livemd
#
# Exit 0 when every cell evaluated; otherwise the failing cell's number, its first line
# and the exception, and exit 1. Needs the network the first time (Kino is fetched into
# Mix.install's cache), so this is run by hand and its run recorded, not a gate step.
# What the gate does check offline is in test/beam_mcp/livebook_test.exs.

[path] = System.argv()
source = File.read!(path)

cells =
  ~r/```elixir\n(.*?)```/s
  |> Regex.scan(source)
  |> Enum.map(fn [_, code] -> code end)

IO.puts("#{path}: #{length(cells)} Elixir cells")

{_binding, failed} =
  cells
  |> Enum.with_index(1)
  |> Enum.reduce({[], 0}, fn
    {_code, _i}, {binding, failed} when failed > 0 ->
      {binding, failed}

    {code, i}, {binding, 0} ->
      first = code |> String.split("\n", trim: true) |> List.first()

      try do
        {value, binding} = Code.eval_string(code, binding, file: Path.expand(path), line: 1)
        summary = value |> inspect(limit: 3, printable_limit: 60) |> String.slice(0, 80)
        IO.puts("  cell #{i} ok    #{first}  =>  #{summary}")
        {binding, 0}
      rescue
        e ->
          IO.puts("  cell #{i} FAIL  #{first}")
          IO.puts(Exception.format(:error, e, __STACKTRACE__))
          {binding, i}
      end
  end)

if failed == 0, do: IO.puts("every cell evaluated"), else: System.halt(1)
