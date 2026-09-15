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

  @doc "Every path under lib/ whose non-comment lines, joined, match the regex -- for a shape that spans lines."
  def file_hits(regex) do
    for path <- lib_files(),
        code =
          File.read!(Path.join(@root, path))
          |> String.split("\n")
          |> Enum.reject(&Regex.match?(~r/^\s*#/, &1))
          |> Enum.join("\n"),
        Regex.match?(regex, code),
        do: path
  end

  @doc """
  `{path, line}` for every construction of a struct named by one of `aliases` (e.g. `[[:ToolSpec],
  [:BeamMCP, :ToolSpec]]`) under lib/, read from the AST rather than the text: a `%Mod{}` literal
  outside a pattern position, a `%{__struct__: Mod}` map, or a `Mod.__struct__/0,1` call. Pattern
  positions -- a clause head, the left of `=`, `<-` and `->`, the first argument of `match?/2` --
  are matches, not constructions, and are not reported.
  """
  def struct_constructions(aliases) do
    for path <- lib_files(),
        {:ok, ast} = Code.string_to_quoted(File.read!(Path.join(@root, path))),
        line <- constructions(ast, aliases, false) |> Enum.sort() |> Enum.uniq(),
        do: {path, line}
  end

  defp constructions({op, _, [head, body]}, aliases, _pattern?)
       when op in [:def, :defp, :defmacro, :defmacrop] do
    constructions(head, aliases, true) ++ constructions(body, aliases, false)
  end

  defp constructions({op, _, [lhs, rhs]}, aliases, _pattern?) when op in [:=, :<-, :match?] do
    constructions(lhs, aliases, true) ++ constructions(rhs, aliases, false)
  end

  defp constructions({:->, _, [args, body]}, aliases, _pattern?) do
    constructions(args, aliases, true) ++ constructions(body, aliases, false)
  end

  defp constructions({:%, meta, [{:__aliases__, _, mod}, map]} = node, aliases, pattern?) do
    hit = if mod in aliases and not pattern?, do: [meta[:line]], else: []
    hit ++ constructions(map, aliases, pattern?) ++ constructions_in_rest(node)
  end

  defp constructions({:%{}, meta, fields} = node, aliases, pattern?) when is_list(fields) do
    hit =
      case Keyword.get(fields, :__struct__) do
        {:__aliases__, _, mod} -> if mod in aliases and not pattern?, do: [meta[:line]], else: []
        _ -> []
      end

    hit ++
      Enum.flat_map(fields, &constructions(&1, aliases, pattern?)) ++ constructions_in_rest(node)
  end

  defp constructions(
         {{:., _, [{:__aliases__, _, mod}, :__struct__]}, meta, args},
         aliases,
         pattern?
       ) do
    hit = if mod in aliases and not pattern?, do: [meta[:line]], else: []
    hit ++ constructions(args, aliases, pattern?)
  end

  defp constructions({_, _, args} = node, aliases, pattern?) when is_list(args) do
    Enum.flat_map(args, &constructions(&1, aliases, pattern?)) ++ constructions_in_rest(node)
  end

  defp constructions({a, b}, aliases, pattern?),
    do: constructions(a, aliases, pattern?) ++ constructions(b, aliases, pattern?)

  defp constructions(list, aliases, pattern?) when is_list(list),
    do: Enum.flat_map(list, &constructions(&1, aliases, pattern?))

  defp constructions(_, _, _), do: []

  # Nothing to walk beside the args a node already exposed.
  defp constructions_in_rest(_node), do: []

  def format(hits),
    do: Enum.map_join(hits, "\n  ", fn {p, n, t} -> "#{p}:#{n}: #{String.trim(t)}" end)
end
