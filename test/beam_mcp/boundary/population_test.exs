# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Boundary.PopulationTest do
  # boundary: the censuses read what the compiler compiles
  # The shared reader walks `lib/**/*.ex`. That is the whole application only while nothing
  # else compiles into it: Mix also compiles Erlang under `src/` by default, and `elixirc_paths`
  # could name another directory. This census pins both, so that "every code line under lib/"
  # means every code line in the package.
  use ExUnit.Case, async: true
  alias BeamMCP.Boundary

  test "nothing compiles into the application from outside lib/: no Erlang sources, no other elixirc path" do
    root = Boundary.root()
    erlang = Path.wildcard(Path.join(root, "{src,lib}/**/*.{erl,yrl,xrl,core,hrl}"))
    assert erlang == [], "sources the reader would not see:\n  " <> Enum.join(erlang, "\n  ")
    config = Mix.Project.config()
    assert config[:erlc_paths] in [nil, ["src"]]

    assert config[:elixirc_paths] == ["lib", "test/support"],
           "test env: lib and the test support only"

    # The other environments' clause, from the source: the test env cannot evaluate it.
    assert File.read!(Path.join(root, "mix.exs")) =~ ~s|defp elixirc_paths(_), do: ["lib"]|
    # Mix's own compilers and no other: nothing else generates code into the application.
    assert config[:compilers] == nil
    # And no macro, no quote and no compiler call under lib/: code that runs at compile time
    # leaves no call in the beam, so the artefact censuses cannot see it; the text holds it here.
    # Two allowances, by their exact lines: the package reads its own version from mix.exs, and
    # the tracer's threat model names the loader it does not call.
    compile_time =
      for {_, _, text} = hit <-
            Boundary.hits(
              ~r/\bdefmacrop?\b|\bdefguardp?\b|\bu?n?quote(_splicing)?\b|:elixir\w*\b|:compile\b|:erl_(eval|parse|scan)\b|:code\.load\w*\b|\bCode\b(?!\.ensure_)|Elixir\.(Code|EEx|Mix)\b|\bEEx\b|\bMix\b|:"[^"]*\\[xu]/
            ),
          String.trim(text) not in [
            "@server_version Mix.Project.config()[:version]",
            "dispatch function, replace a module with `:code.load_binary/3`, or trace every process"
          ],
          do: hit

    assert compile_time == [],
           "compile-time code under lib/:\n  " <> Boundary.format(compile_time)

    # And no directive that would bring one of those modules in under another name -- an
    # import, an alias or a require of Code, EEx, Mix or an Erlang evaluator, however it is
    # spelled and across however many lines (a lane brought Code in by `import`, by an alias
    # split over three lines, and `:erl_eval` by `alias :erl_eval, as: EE`).
    renamed =
      Boundary.file_hits(
        ~r/\b(import|alias|require)\b[\s(]*((Elixir\.)?(\{[^}]*)?\b(Code|EEx|Mix|File|System|Path|Application)\b|:(erl_\w+|elixir\w*|compile|code|os|file|prim_file|filelib|init|application)\b)/
      )

    assert renamed == [],
           "a compile-time module renamed under lib/:\n  " <> Enum.join(renamed, "\n  ")

    assert length(Boundary.hits(~r/\bMix\./)) == 1

    # Nor a read of the environment or the disk, at any position -- a module body runs at
    # compile time and could bake a secret into the beam.
    reads =
      Boundary.hits(
        ~r/:os\.|\bFile\.|:file\.|:prim_file\.|:erl_prim_loader\.|:filelib\.|\bPath\.wildcard|:init\.|System\.(get_env|fetch_env!?|user_home!?|argv|tmp_dir!?|cmd|shell|find_executable)\b|Application\.(get_env|fetch_env!?|compile_env!?|get_all_env)\b|:application\.get_(all_)?env|:"Elixir\.(File|System|Path|Application|Code|EEx|Mix)"/
      )

    assert reads == [], "environment or disk reads under lib/:\n  " <> Boundary.format(reads)

    assert Boundary.lib_files() != []
  end

  # The artefact, not only the source: a beam left in the build by a source that is gone
  # (Mix does not prune Erlang artefacts) is still in the application's module list, and a
  # census over lib/ would never see it.
  test "every module the built application lists is a BeamMCP module, and the list is the ebin" do
    modules = Boundary.app_modules()
    assert modules != []
    # The `.app` is regenerated on a one-second mtime; the ebin is the artefact. They must agree.
    assert Enum.sort(modules) == Enum.sort(Boundary.ebin_modules())

    strays =
      for m <- modules, not String.starts_with?(Atom.to_string(m), "Elixir.BeamMCP."), do: m

    assert strays == [],
           "modules in the built application from outside BeamMCP: #{inspect(strays)}"
  end

  test "the dependencies mix.exs declares are exactly the listed ones" do
    # A `path:` dependency never reaches the lock; the declaration is pinned beside it.
    assert Mix.Project.config()[:deps] |> Enum.map(&elem(&1, 0)) ==
             [:jason, :telemetry, :plug, :bandit, :credo, :ex_doc, :stream_data]
  end

  test "the dependencies the lock file holds are exactly the listed ones" do
    lock = Boundary.root() |> Path.join("mix.lock") |> File.read!()
    # Every entry, digits included: `oauth2`, `x509`, `argon2_elixir` are the shape of what
    # entries 2, 3 and 8 exist to keep out, and a lane showed `[a-z_]+` blind to them.
    names = Regex.scan(~r/^  "([a-z0-9_]+)":/m, lock) |> Enum.map(fn [_, n] -> n end)

    assert length(names) == length(Regex.scan(~r/^  "/m, lock)),
           "a lock entry the pattern did not read"

    assert Enum.sort(names) ==
             ~w(bandit bunt credo earmark_parser ex_doc file_system hpax jason makeup makeup_elixir makeup_erlang mime nimble_parsec plug plug_crypto stream_data telemetry thousand_island websock)
  end
end
