# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.GrowthTableTest do
  @moduledoc """
  Every value set a public type spells out as a union of atoms says, on
  `docs/api-stability.md`, whether it may grow at a minor (OPEN) or only at a major (CLOSED).

  The population is read from the compiled types (`Code.Typespec.fetch_types/1` over every
  module compiled from `lib/`, the public-API census's population), never from a list: a named
  `@type` whose whole definition is a union of literal atoms, and a public struct's field
  typed as one. Each needs exactly one row, with exactly the atoms the type has, so a union
  that grows, shrinks or appears without its row is a failure, and so is a row whose type is
  gone. Unions nested deeper (inside a list, a tuple, an error reason) are not rows: the page's
  default covers them, and the default is OPEN.
  """
  use ExUnit.Case, async: true

  @page "docs/api-stability.md"

  # {"Module.name/arity", nil | field, [atoms]} for every union the compiled types carry:
  # `@type` and `@opaque`, with parameters or without (`@typep` is not public).
  defp population do
    for m <- BeamMCP.PublicAPI.modules(),
        {:ok, types} <- [Code.Typespec.fetch_types(m)],
        {kind, {name, ast, args}} <- types,
        kind in [:type, :opaque],
        entry <- unions("#{inspect(m)}.#{name}/#{length(args)}", ast),
        do: entry
  end

  defp unions(type, ast) do
    case atoms(ast) do
      [_, _ | _] = atoms -> [{type, nil, atoms}]
      _ -> fields(type, ast)
    end
  end

  # A struct's type: `%{__struct__: M, field => type, ...}`; a field whose type is a union of
  # literal atoms is a row of its own.
  defp fields(type, {:type, _, :map, pairs}) when is_list(pairs) do
    struct? = Enum.any?(pairs, &match?({:type, _, _, [{:atom, _, :__struct__}, _]}, &1))

    for {:type, _, _, [{:atom, _, field}, field_type]} <- pairs,
        struct?,
        field != :__struct__,
        [_, _ | _] = atoms <- [atoms(field_type)],
        do: {type, Atom.to_string(field), atoms}
  end

  defp fields(_type, _ast), do: []

  defp atoms({:type, _, :union, members}) do
    if Enum.all?(members, &match?({:atom, _, _}, &1)),
      do: Enum.sort(for({:atom, _, a} <- members, do: a)),
      else: nil
  end

  defp atoms(_), do: nil

  # | `t:Mod.name/0` | `:a` `:b` | OPEN |   or   | `t:Mod.name/0` field `f` | ... | CLOSED |
  defp rows do
    ~r/^\| `t:([A-Za-z0-9_.]+\/\d+)`(?: field `([a-z_]+)`)? \| ((?:`:[a-z0-9_]+` ?)+) \| (OPEN|CLOSED) \|/m
    |> Regex.scan(File.read!(@page), capture: :all_but_first)
    |> Enum.map(fn [type, field, values, growth] ->
      atoms =
        ~r/`:([a-z0-9_]+)`/
        |> Regex.scan(values, capture: :all_but_first)
        |> List.flatten()
        |> Enum.map(&String.to_atom/1)
        |> Enum.sort()

      {{type, if(field == "", do: nil, else: field)}, {atoms, growth}}
    end)
  end

  test "every atom union in a public type has exactly one row, with its atoms and OPEN or CLOSED" do
    pop = population()
    rows = rows()
    assert pop != [], "the census read no union: its reader is broken, not the tree clean"

    keys = Enum.map(rows, &elem(&1, 0))
    assert keys == Enum.uniq(keys), "a type has two rows on #{@page}"
    table = Map.new(rows)

    for {type, field, atoms} <- pop do
      label = if field, do: "#{type} field `#{field}`", else: type

      assert {row_atoms, _growth} = Map.get(table, {type, field}),
             "#{label} (#{inspect(atoms)}) has no row in #{@page}'s growth table"

      assert row_atoms == atoms,
             "#{label}: the row says #{inspect(row_atoms)}, the compiled type #{inspect(atoms)}"
    end

    stale = Map.keys(table) -- Enum.map(pop, fn {t, f, _} -> {t, f} end)
    assert stale == [], "rows for types that are not atom unions any more: #{inspect(stale)}"
  end
end
