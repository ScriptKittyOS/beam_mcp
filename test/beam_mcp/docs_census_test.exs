# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.DocsCensusTest do
  # Every function the documentation names exists at the stated arity, and every module it
  # names is loadable. The population is the tracked prose -- README, CHANGELOG, docs/*.md,
  # the notebook -- and every @moduledoc and @doc string the compiled modules carry, read
  # from the beams with Code.fetch_docs/1 rather than from the source. A reference is a
  # backticked `BeamMCP.Module.fun/N` or `BeamMCP.Module`; references to other packages'
  # modules are not this test's to check and are skipped by prefix. The CHANGELOG names
  # functions that no longer exist on purpose (a removed `BeamMCP.ToolCatalog.all/0`, say):
  # its population is the current release's section only, cut at the first earlier heading.
  use ExUnit.Case, async: true

  @root Path.expand("../..", __DIR__)
  # ExDoc's forms: `Mod`, `Mod.fun/N`, `c:Mod.callback/N`, `t:Mod.type/N`.
  @ref ~r/`(c:|t:)?(BeamMCP(?:\.[A-Z][A-Za-z0-9]*)+)(?:\.([a-z_][A-Za-z0-9_?!]*)\/(\d+))?`/

  defp tracked(patterns) do
    {out, 0} = System.cmd("git", ["ls-files", "--" | patterns], cd: @root)
    String.split(out, "\n", trim: true)
  end

  defp prose_population do
    for path <- tracked(["README.md", "CHANGELOG.md", "docs/*.md", "livebooks/*.livemd"]) do
      text = File.read!(Path.join(@root, path))

      text =
        if path == "CHANGELOG.md" do
          # The top section only: [Unreleased] or the newest version heading.
          [_, first | _] = String.split(text, ~r/^## \[/m)
          first
        else
          text
        end

      {path, text}
    end
  end

  defp doc_population do
    for path <- tracked(["lib/**/*.ex"]),
        module <- modules_in(path),
        {:docs_v1, _, _, _, moduledoc, _, docs} = Code.fetch_docs(module),
        {where, text} <- [
          {"@moduledoc", doc_text(moduledoc)}
          | Enum.map(docs, &{"@doc #{inspect(elem(&1, 0))}", doc_text(elem(&1, 3))})
        ],
        is_binary(text) do
      {"#{inspect(module)} #{where}", module, text}
    end
  end

  defp modules_in(path) do
    ~r/^\s*defmodule ([A-Z][A-Za-z0-9_.]*) do/m
    |> Regex.scan(File.read!(Path.join(@root, path)), capture: :all_but_first)
    |> List.flatten()
    |> Enum.map(&Module.concat([&1]))
    |> Enum.filter(&Code.ensure_loaded?/1)
  end

  defp doc_text(%{"en" => text}), do: text
  defp doc_text(_), do: nil

  defp refs(text) do
    for [kind, mod, fun, arity] <-
          Regex.scan(@ref, text, capture: :all_but_first) |> Enum.map(&pad4/1) do
      {Module.concat([mod]), fun, arity, kind}
    end
  end

  # Inside a module's own docs a bare `fun/N` is that module's, which is how ExDoc links it.
  @bare ~r/(?<![\w.])`([a-z_][A-Za-z0-9_?!]*)\/(\d+)`/

  defp bare_refs(module, text) do
    for [fun, arity] <- Regex.scan(@bare, text, capture: :all_but_first),
        do: {module, fun, arity, ""}
  end

  defp pad4([kind, mod]), do: [kind, mod, "", ""]
  defp pad4([kind, mod, fun, arity]), do: [kind, mod, fun, arity]

  defp missing({module, "", "", _kind}) do
    if Code.ensure_loaded?(module), do: [], else: ["#{inspect(module)} (module)"]
  end

  # A function is exported or a macro; a callback (`c:`) is in behaviour_info; a type (`t:`)
  # is in the module's typespecs. ExDoc links each form only to its own kind, so the census
  # holds a reference to the kind its prefix claims -- a callback written without `c:` is a
  # warning from ExDoc, which the gate's docs step already refuses.
  defp missing({module, fun, arity, kind}) do
    name = String.to_atom(fun)
    arity = String.to_integer(arity)
    shown = "#{kind}#{inspect(module)}.#{fun}/#{arity}"

    cond do
      not Code.ensure_loaded?(module) -> ["#{shown} (module)"]
      defined?(kind, module, name, arity) -> []
      true -> [shown]
    end
  end

  # A bare name is the module's own function, macro or callback (a behaviour's docs name
  # its callbacks bare); qualified, a callback needs `c:` and a type `t:`.
  defp defined?("", module, name, arity) do
    function_exported?(module, name, arity) or macro_exported?(module, name, arity) or
      callback?(module, name, arity)
  end

  defp defined?("c:", module, name, arity), do: callback?(module, name, arity)
  defp defined?("t:", module, name, arity), do: type?(module, name, arity)

  defp callback?(module, name, arity) do
    function_exported?(module, :behaviour_info, 1) and
      {name, arity} in module.behaviour_info(:callbacks)
  end

  defp type?(module, name, arity) do
    case Code.Typespec.fetch_types(module) do
      {:ok, types} ->
        Enum.any?(types, fn {_kind, {n, _, args}} -> n == name and length(args) == arity end)

      :error ->
        false
    end
  end

  # A module the current release removed is named on purpose -- by the CHANGELOG entry that
  # records the break and by the moduledoc of what replaced it. The set is derived from the
  # CHANGELOG's own sentence for a break, "`Old` is replaced by", in the top section only,
  # so it holds exactly the modules this release says it removed and nothing anyone listed.
  defp removed do
    {_, changelog} = Enum.find(prose_population(), &(elem(&1, 0) == "CHANGELOG.md"))

    ~r/`(BeamMCP(?:\.[A-Z][A-Za-z0-9]*)+)` is replaced by/
    |> Regex.scan(changelog, capture: :all_but_first)
    |> List.flatten()
    |> Enum.map(&Module.concat([&1]))
  end

  test "every BeamMCP module and function the prose and the compiled docs name exists at that arity" do
    prose = prose_population()
    docs = doc_population()
    assert length(prose) + length(docs) > 20
    removed = removed()

    references =
      Enum.flat_map(prose, fn {where, text} -> Enum.map(refs(text), &{where, &1}) end) ++
        Enum.flat_map(docs, fn {where, module, text} ->
          Enum.map(refs(text) ++ bare_refs(module, text), &{where, &1})
        end)

    # A census over nothing proves nothing: the count is asserted, not assumed.
    assert length(references) > 100, "only #{length(references)} references found"

    found =
      for {where, {module, _, _, _} = ref} <- references,
          module not in removed,
          reason <- missing(ref),
          do: "#{where}: #{reason}"

    assert found == [],
           "named in the docs, absent from the code:\n  " <> Enum.join(Enum.uniq(found), "\n  ")
  end
end
