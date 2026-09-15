# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Boundary do
  @moduledoc false
  # The one reader the boundary censuses share: every CODE line of every `.ex` file under lib/
  # -- comment lines dropped, doc strings kept (a doc that names a primitive is read too, so a
  # census that must allow prose says so by pattern). The population is `Path.wildcard`, the
  # same files `mix compile` just read, so an untracked plant is seen (the gate's REUSE and
  # publication steps read `git ls-files` because they are about what is published; a census
  # over code is about what compiles).

  @root Path.expand("../../..", __DIR__)

  def root, do: @root

  @doc "Every `.ex` path under lib/, relative to the root, sorted."
  def lib_files do
    @root
    |> Path.join("lib/**/*.ex")
    |> Path.wildcard()
    |> Enum.map(&Path.relative_to(&1, @root))
    |> Enum.sort()
  end

  @doc "`{path, line_number, text}` for every non-comment line under lib/ matching the regex."
  def hits(regex) do
    for path <- lib_files(),
        {text, n} <- Enum.with_index(File.read!(Path.join(@root, path)) |> String.split("\n"), 1),
        not Regex.match?(~r/^\s*#/, text),
        Regex.match?(regex, text),
        do: {path, n, text}
  end

  def format(hits),
    do: Enum.map_join(hits, "\n  ", fn {p, n, t} -> "#{p}:#{n}: #{String.trim(t)}" end)
end
