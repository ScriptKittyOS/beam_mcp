# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Boundary do
  @moduledoc false
  # The one reader the boundary censuses share: every CODE line of every `.ex` file under lib/
  # -- comment lines dropped (a `#` line that carries a `#{` anywhere is an interpolation inside
  # a string, not a comment, and is kept), doc strings kept (a doc that names a primitive is read
  # too, so a census that must allow prose says so by pattern). The population is
  # `Path.wildcard`, the same files `mix compile` just read, so an untracked plant is seen (the
  # gate's REUSE and
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
        not comment?(text),
        Regex.match?(regex, text),
        do: {path, n, text}
  end

  @doc "Every path under lib/ whose non-comment lines, joined, match the regex -- for a shape that spans lines."
  def file_hits(regex) do
    for path <- lib_files(),
        code =
          File.read!(Path.join(@root, path))
          |> String.split("\n")
          |> Enum.reject(&comment?/1)
          |> Enum.join("\n"),
        Regex.match?(regex, code),
        do: path
  end

  @doc """
  The modules compiled from lib/: every beam in the build's ebin whose compile-time source is
  under lib/ (the test build compiles test/support into the same directory). The ebin, not the
  `.app` file: Mix regenerates the `.app` on the directory's mtime at one-second granularity, so
  a module compiled in the same second as the previous `.app` is absent from it -- measured by a
  review lane, a green on a planted violation. The ebin's own limit: it is what the last compile
  left, so a beam Mix's manifest does not own -- copied in, or left by a compile whose manifest
  was lost -- whose `:source` says lib/ is counted until it is deleted (Mix prunes the beams of
  removed sources it tracked; the exposure is beams outside the manifest). Not measured; stated.
  """
  def lib_modules do
    for path <- Path.wildcard(Path.join(Mix.Project.compile_path(), "*.beam")),
        m = path |> Path.basename(".beam") |> String.to_atom(),
        {:module, ^m} = Code.ensure_loaded(m),
        source = m.module_info(:compile)[:source],
        String.starts_with?(to_string(source), Path.join(@root, "lib")),
        do: m
  end

  @doc """
  The test citations a page makes: `[{path, [name]}]` in page order. A citation is a test
  file's path in backticks followed, on the same line, by one or more test names in straight
  double quotes: `` `test/x_test.exs` "a name" "another" ``; a name belongs to the last path
  on its line. Read by the will-not-implement census and the threat-model census, so a page
  that cites a test is held to the tree the same way wherever it lives.
  """
  def citations(text) do
    for line <- String.split(text, "\n"),
        Regex.match?(~r/`test\/[^`]+_test\.exs`/, line),
        {path, names} <- cite_line(line),
        do: {path, names}
  end

  # The scan starts at the line's first backtick path: a table row's prose column may carry
  # quotes of its own -- a wire message in backticks, an escaped `\"` -- and read from the
  # start of the line those pair up wrongly and swallow the path (a lane found a row whose
  # three citations the reader returned as none). A name may not contain a quote.
  defp cite_line(line) do
    [_prose, from_path] = Regex.split(~r/(?=`test\/[^`]+_test\.exs`)/, line, parts: 2)

    ~r/`(test\/[^`]+_test\.exs)`|"([^"]+)"/
    |> Regex.scan(from_path)
    |> Enum.reduce([], fn
      [_, path], acc when path != "" -> [{path, []} | acc]
      [_, "", name], [{path, names} | rest] -> [{path, names ++ [name]} | rest]
      [_, "", _name], [] -> []
    end)
    |> Enum.reverse()
  end

  @doc """
  Every test the page cites exists, by path and by name, and is live; every citation names a
  test. Returns the defects. Liveness is ExUnit's answer, not a text reader's: the cited file's
  first `defmodule` is loaded (required from the path if the suite has not loaded it) and the
  test list ExUnit generates on it read -- a test is live when it is there and carries no `skip` tag,
  which is where `@tag`, `@describetag` and `@moduletag` all end up, in every spelling. A
  commented-out test, or a `test "..."` inside a string, is not in that list. What this does
  not see: an `--exclude` at the runner (`test/test_helper.exs` excludes `:hot_reload` under
  cover), which is the runner's, not the module's.
  """
  def citation_defects(text, root) do
    Enum.flat_map(citations(text), fn {path, names} -> citation_defect(path, names, root) end)
  end

  defp citation_defect(path, names, root) do
    full = Path.join(root, path)

    cond do
      not File.exists?(full) -> ["#{path} is not in the tree"]
      names == [] -> ["#{path} is cited without a test name"]
      true -> unnamed_tests(path, names, live_tests(full))
    end
  end

  defp unnamed_tests(path, names, live) do
    for n <- names, not MapSet.member?(live, n), do: "#{path} names no live test #{inspect(n)}"
  end

  # The names of the file's live tests, without the "test " / "property " prefix ExUnit adds.
  defp live_tests(full) do
    source = File.read!(full)
    [_, module_name] = Regex.run(~r/^defmodule\s+([A-Z][\w.]*)/m, source)
    module = Module.concat([module_name])
    Code.ensure_loaded?(module) or Code.require_file(full)

    # A skip tag is any truthy value: `:skip` is `skip: true`, `skip: "why"` is a string. The
    # name ExUnit holds is "test <describe> <name>"; the page cites the bare name.
    for %ExUnit.Test{name: name, tags: tags} <- module.__ex_unit__().tests,
        !Map.get(tags, :skip, false),
        into: MapSet.new() do
      name
      |> Atom.to_string()
      |> String.replace(~r/^(?:test|property) /, "")
      |> String.replace_prefix(describe_prefix(tags), "")
    end
  end

  defp describe_prefix(%{describe: describe}) when is_binary(describe), do: describe <> " "
  defp describe_prefix(_), do: ""

  @doc "Every module the built application's `.app` file lists."
  def app_modules do
    Application.load(:beam_mcp)
    {:ok, modules} = :application.get_key(:beam_mcp, :modules)
    modules
  end

  @doc "Every beam in the build's ebin, as a module name."
  def ebin_modules do
    for path <- Path.wildcard(Path.join(Mix.Project.compile_path(), "*.beam")),
        do: path |> Path.basename(".beam") |> String.to_atom()
  end

  @doc """
  Every atom in the compiled forms of the lib/ modules that names a loadable module -- a call
  target, a `-file`/`-compile` attribute, or a module handed somewhere as data (a child spec's
  `{m, f, a}`, a handler's module). What the package can reach by naming, not only by calling.
  """
  def module_atoms do
    lib = lib_modules()

    for m <- lib,
        {:ok, {_, [{:abstract_code, {:raw_abstract_v1, forms}}]}} =
          :beam_lib.chunks(:code.which(m), [:abstract_code]),
        atom <- atoms(forms, []),
        atom not in lib,
        module_name?(atom),
        uniq: true,
        do: atom
  end

  # An `Elixir.`-prefixed atom is a module name by construction, loadable here or not (a lane
  # named `Finch` in a child spec with no Finch installed); an Erlang-style atom is a module
  # name only if this VM can load it.
  defp module_name?(atom) do
    String.starts_with?(Atom.to_string(atom), "Elixir.") or
      match?({:module, _}, Code.ensure_loaded(atom))
  end

  defp atoms({:atom, _, a}, acc), do: [a | acc]

  defp atoms(tuple, acc) when is_tuple(tuple),
    do: Enum.reduce(Tuple.to_list(tuple), acc, &atoms(&1, &2))

  defp atoms(list, acc) when is_list(list), do: Enum.reduce(list, acc, &atoms(&1, &2))
  defp atoms(_, acc), do: acc

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

  # A key is a site too (`%{BeamMCP.ToolSpec => true}` puts the atom in a map with no
  # `__struct__` at all -- a review lane's plant); it is read as a value.
  defp field_sites({:map_field_exact, _, {:atom, _, key} = k, value}, atom, :map, acc),
    do: sites(value, atom, {:pattern, key}, sites(k, atom, :value, acc))

  defp field_sites({:map_field_assoc, _, {:atom, _, key} = k, value}, atom, :map, acc),
    do: sites(value, atom, {:construction, key}, sites(k, atom, :value, acc))

  defp field_sites({_, _, {:atom, _, key} = k, value}, atom, :update, acc),
    do: sites(value, atom, {:update, key}, sites(k, atom, :value, acc))

  defp field_sites({_, _, key, value}, atom, _kind, acc),
    do: sites(value, atom, :value, sites(key, atom, :value, acc))

  @doc """
  Every name reached by dot syntax under lib/ (`x.name`), from the compiled forms: a field access
  and a call without parentheses through a runtime module compile to the same branch --
  `elixir_erl_pass:no_parens_remote(X, name)` -- so the artefact cannot tell them apart, but it
  can list every name, and a census can pin the list.
  """
  def dotted_names do
    for m <- lib_modules(),
        {:ok, {_, [{:abstract_code, {:raw_abstract_v1, forms}}]}} =
          :beam_lib.chunks(:code.which(m), [:abstract_code]),
        name <- dotted(forms, []),
        uniq: true,
        do: name
  end

  defp dotted(
         {:call, _, {:remote, _, {:atom, _, :elixir_erl_pass}, {:atom, _, :no_parens_remote}},
          [_, {:atom, _, name}]},
         acc
       ),
       do: [name | acc]

  defp dotted(tuple, acc) when is_tuple(tuple),
    do: Enum.reduce(Tuple.to_list(tuple), acc, &dotted(&1, &2))

  defp dotted(list, acc) when is_list(list), do: Enum.reduce(list, acc, &dotted(&1, &2))
  defp dotted(_, acc), do: acc

  def generated?(0), do: true
  def generated?(location) when is_list(location), do: Keyword.get(location, :generated, false)
  def generated?(_), do: false

  @doc "A comment line: begins with `#` and carries no interpolation."
  def comment?(text), do: Regex.match?(~r/^\s*#/, text) and not String.contains?(text, "\#{")

  def format(hits),
    do: Enum.map_join(hits, "\n  ", fn {p, n, t} -> "#{p}:#{n}: #{String.trim(t)}" end)
end
