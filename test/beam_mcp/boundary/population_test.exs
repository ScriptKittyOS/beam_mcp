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

    assert Boundary.lib_files() != []
  end

  # The artefact, not only the source: a beam left in the build by a source that is gone
  # (Mix does not prune Erlang artefacts) is still in the application's module list, and a
  # census over lib/ would never see it.
  test "every module the built application lists is a BeamMCP module" do
    Application.load(:beam_mcp)
    {:ok, modules} = :application.get_key(:beam_mcp, :modules)
    assert modules != []

    strays =
      for m <- modules, not String.starts_with?(Atom.to_string(m), "Elixir.BeamMCP."), do: m

    assert strays == [],
           "modules in the built application from outside BeamMCP: #{inspect(strays)}"
  end
end
