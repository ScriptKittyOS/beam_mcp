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
  The modules compiled from lib/ -- the built application's module list, kept to those whose
  compile-time source is under lib/ (the test build compiles test/support into the same app).
  """
  def lib_modules do
    Application.load(:beam_mcp)
    {:ok, modules} = :application.get_key(:beam_mcp, :modules)

    for m <- modules,
        source = m.module_info(:compile)[:source],
        String.starts_with?(to_string(source), Path.join(@root, "lib")),
        do: m
  end

  @doc """
  `{edges, unresolved}` from `:xref` over the compiled lib/ modules, BIFs included: every call
  `{{caller_m, f, a}, {callee_m, f, a}}` the beams make, and every call whose module or function
  is only known at runtime (`:"$M_EXPR"` / `:"$F_EXPR"`).
  """
  def xref do
    {:ok, ref} = :xref.start([])

    try do
      :xref.set_default(ref, warnings: false, verbose: false, builtins: true)
      for m <- lib_modules(), do: {:ok, _} = :xref.add_module(ref, :code.which(m))
      {:ok, edges} = :xref.q(ref, ~c"E")
      {:ok, unresolved} = :xref.q(ref, ~c"UC")
      {edges, unresolved}
    after
      :xref.stop(ref)
    end
  end

  @doc """
  Every site of `atom` in the compiled forms of the lib/ modules, as `{module, location, context}`:
  the context is `{:pattern, key}` inside a map pattern (Erlang abstract format writes a pattern's
  fields as `map_field_exact` and a construction's as `map_field_assoc`; an update `%{m | k: v}` is
  the four-element map form and is reported as `{:update, key}`), `{:construction, key}` inside a
  map literal, or `:value` anywhere else. Compiler-generated sites carry location `0` or a
  `generated: true` annotation.
  """
  def atom_sites(atom) do
    for m <- lib_modules(),
        {:ok, {_, [{:abstract_code, {:raw_abstract_v1, forms}}]}} =
          :beam_lib.chunks(:code.which(m), [:abstract_code]),
        {location, context} <- sites(forms, atom, :value, []),
        do: {m, location, context}
  end

  defp sites({:map, _, fields}, atom, _ctx, acc) when is_list(fields),
    do: Enum.reduce(fields, acc, &field_sites(&1, atom, :map, &2))

  defp sites({:map, _, expr, fields}, atom, ctx, acc) do
    acc = sites(expr, atom, ctx, acc)
    Enum.reduce(fields, acc, &field_sites(&1, atom, :update, &2))
  end

  defp sites({:atom, location, atom}, atom, ctx, acc), do: [{location, ctx} | acc]

  defp sites(tuple, atom, ctx, acc) when is_tuple(tuple),
    do: Enum.reduce(Tuple.to_list(tuple), acc, &sites(&1, atom, ctx, &2))

  defp sites(list, atom, ctx, acc) when is_list(list),
    do: Enum.reduce(list, acc, &sites(&1, atom, ctx, &2))

  defp sites(_, _, _, acc), do: acc

  defp field_sites({:map_field_exact, _, {:atom, _, key}, value}, atom, :map, acc),
    do: sites(value, atom, {:pattern, key}, acc)

  defp field_sites({:map_field_assoc, _, {:atom, _, key}, value}, atom, :map, acc),
    do: sites(value, atom, {:construction, key}, acc)

  defp field_sites({_, _, {:atom, _, key}, value}, atom, :update, acc),
    do: sites(value, atom, {:update, key}, acc)

  defp field_sites({_, _, key, value}, atom, _kind, acc),
    do: sites(value, atom, :value, sites(key, atom, :value, acc))

  def generated?(0), do: true
  def generated?(location) when is_list(location), do: Keyword.get(location, :generated, false)
  def generated?(_), do: false

  def format(hits),
    do: Enum.map_join(hits, "\n  ", fn {p, n, t} -> "#{p}:#{n}: #{String.trim(t)}" end)
end
