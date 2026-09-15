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
  outside a pattern position, a `%{__struct__: Mod}` map, a `Mod.__struct__/0,1` call, a
  `struct/1,2` or `struct!/1,2` call on the module, or a `Map.put(_, :__struct__, Mod)`. Inside
  the module's own `defmodule`, `__MODULE__` names it and counts the same. Pattern positions --
  a clause head, the left of `=`, `<-` and `->`, the first argument of `Kernel.match?/2` -- are
  matches, not constructions; a `@type`, `@typep`, `@opaque`, `@spec` or `@callback` is a
  declaration and is not walked.
  """
  def struct_constructions(aliases) do
    for path <- lib_files(),
        {:ok, ast} = Code.string_to_quoted(File.read!(Path.join(@root, path))),
        line <- ast |> constructions(aliases, false, false) |> Enum.sort() |> Enum.uniq(),
        do: {path, line}
  end

  # self? -- inside a `defmodule` whose name is one of the aliases, so `__MODULE__` is it.
  defp constructions({:defmodule, _, [{:__aliases__, _, mod}, body]}, aliases, pattern?, _self?) do
    constructions(body, aliases, pattern?, mod in aliases)
  end

  defp constructions({:@, _, [{attr, _, _}]}, _aliases, _pattern?, _self?)
       when attr in [:type, :typep, :opaque, :spec, :callback, :macrocallback] do
    []
  end

  defp constructions({op, _, [head, body]}, aliases, _pattern?, self?)
       when op in [:def, :defp, :defmacro, :defmacrop] do
    constructions(head, aliases, true, self?) ++ constructions(body, aliases, false, self?)
  end

  defp constructions({op, _, [lhs, rhs]}, aliases, _pattern?, self?)
       when op in [:=, :<-, :match?] do
    constructions(lhs, aliases, true, self?) ++ constructions(rhs, aliases, false, self?)
  end

  defp constructions(
         {{:., _, [{:__aliases__, _, [:Kernel]}, :match?]}, _, [lhs, rhs]},
         aliases,
         _p,
         self?
       ) do
    constructions(lhs, aliases, true, self?) ++ constructions(rhs, aliases, false, self?)
  end

  defp constructions({:->, _, [args, body]}, aliases, _pattern?, self?) do
    constructions(args, aliases, true, self?) ++ constructions(body, aliases, false, self?)
  end

  defp constructions({:%, meta, [target, map]}, aliases, pattern?, self?) do
    hit(target, meta, aliases, pattern?, self?) ++ constructions(map, aliases, pattern?, self?)
  end

  defp constructions({:%{}, meta, fields}, aliases, pattern?, self?) when is_list(fields) do
    hit =
      case Keyword.get(fields, :__struct__) do
        nil -> []
        target -> hit(target, meta, aliases, pattern?, self?)
      end

    hit ++ Enum.flat_map(fields, &constructions(&1, aliases, pattern?, self?))
  end

  defp constructions({{:., _, [target, :__struct__]}, meta, args}, aliases, pattern?, self?) do
    hit(target, meta, aliases, pattern?, self?) ++ constructions(args, aliases, pattern?, self?)
  end

  defp constructions({op, meta, [target | rest]}, aliases, pattern?, self?)
       when op in [:struct, :struct!] do
    hit(target, meta, aliases, pattern?, self?) ++ constructions(rest, aliases, pattern?, self?)
  end

  defp constructions(
         {{:., _, [{:__aliases__, _, [:Map]}, :put]}, meta, [m, :__struct__, target]},
         aliases,
         pattern?,
         self?
       ) do
    hit(target, meta, aliases, pattern?, self?) ++ constructions(m, aliases, pattern?, self?)
  end

  defp constructions({_, _, args}, aliases, pattern?, self?) when is_list(args) do
    Enum.flat_map(args, &constructions(&1, aliases, pattern?, self?))
  end

  defp constructions({a, b}, aliases, pattern?, self?),
    do: constructions(a, aliases, pattern?, self?) ++ constructions(b, aliases, pattern?, self?)

  defp constructions(list, aliases, pattern?, self?) when is_list(list),
    do: Enum.flat_map(list, &constructions(&1, aliases, pattern?, self?))

  defp constructions(_, _, _, _), do: []

  defp hit(_target, _meta, _aliases, true, _self?), do: []

  defp hit({:__aliases__, _, mod}, meta, aliases, false, _self?),
    do: if(mod in aliases, do: [meta[:line]], else: [])

  defp hit({:__MODULE__, _, _}, meta, _aliases, false, true), do: [meta[:line]]
  defp hit(_, _, _, _, _), do: []

  def format(hits),
    do: Enum.map_join(hits, "\n  ", fn {p, n, t} -> "#{p}:#{n}: #{String.trim(t)}" end)
end
