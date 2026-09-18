# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.PublicAPICensusTest do
  # The public surface changes only on the record.
  #
  # The population is what ex_doc lists -- every function, macro, callback and type with docs
  # in the compiled application's chunks (`BeamMCP.PublicAPI.population/0`; `@moduledoc false`
  # and `@doc false` are the private surface) -- held to `docs/public-api.txt`, and that file
  # held to the CHANGELOG. The rule, the owner's, verbatim in the slice record and restated in
  # docs/api-stability.md: a documented public entry may change only if, in the same change,
  # (1) the baseline moves with it, (2) the CHANGELOG's Unreleased section names the exact
  # module + name + arity, and (3) the kind-specific condition holds -- an entry still present
  # and leaving later carries `@deprecated` and the CHANGELOG records the deprecation (step one
  # of the three-minor rule); an entry removed, renamed or with its arity or defaults changed
  # must already have been `@deprecated` for three minors, or the CHANGELOG entry must say it
  # is a 0.x documented break at the minor -- a first-time `@deprecated` in the same change
  # does not count; a docs-hidden flip is a removal. Each kind has its one condition set;
  # there is no OR between them.
  #
  # The rule is one pure function, `BeamMCP.PublicAPI.violations/1`, run here twice: on the
  # tree (the census) and on literal fixtures (the pins). The tree today has no deprecation,
  # no hidden module under lib/ and no Unreleased marker, so on the tree alone every rule
  # path is vacuous -- a lane's one-token mutant switched the census off and passed the
  # suite. The fixture runs are what hold each path; `BeamMCP.Fixture.PublicAPI` is what
  # holds the population's reading of a real module.
  #
  # The record is read from the tree, never from git: a removed entry's baseline line stays,
  # marked `removed_in=R`, so the tree carries what left and when. Two hand edits are invisible
  # to a tree-only census -- a line deleted outright, and a removal back-dated to a released
  # number -- the same as editing any pinned list; both are a reviewer's line, said here and
  # on the page so nobody takes this census for more than it is.
  use ExUnit.Case, async: true

  alias BeamMCP.Fixture
  alias BeamMCP.PublicAPI

  @baseline PublicAPI.baseline_path()

  setup_all do
    {:ok,
     version: Mix.Project.config()[:version],
     lines: PublicAPI.read_baseline!(@baseline),
     population: PublicAPI.population(),
     deprecated: PublicAPI.deprecated(),
     sections: PublicAPI.sections(File.read!("CHANGELOG.md"))}
  end

  defp describe_violations(violations) do
    Enum.map_join(violations, "\n  ", fn
      {check, text} when is_binary(text) -> "#{check}: #{text}"
      {check, entry} -> "#{check}: #{PublicAPI.format(entry)}"
    end)
  end

  # ---- the tree -------------------------------------------------------------------------

  test "the tree: the compiled application, the baseline and the CHANGELOG agree under the rule",
       ctx do
    violations =
      PublicAPI.violations(Map.take(ctx, [:version, :lines, :population, :deprecated, :sections]))

    assert violations == [],
           "the public surface is off the record (docs/api-stability.md, \"The census, exactly\"; " <>
             "the writer is `MIX_ENV=test mix run -e \"BeamMCP.PublicAPI.write_baseline!()\"`):\n  " <>
             describe_violations(violations)
  end

  test "the tree: the baseline parses, four kinds, defaults counted, and it is not small", ctx do
    assert ctx.lines != []

    for {{m, kind, name, arity, defaults}, markers} <- ctx.lines do
      assert kind in [:function, :macro, :callback, :type]
      assert is_atom(m) and is_atom(name) and is_integer(arity) and is_integer(defaults)
      for {k, _} <- markers, do: assert(k in ["since", "deprecated_since", "removed_in"])
    end

    kinds = ctx.population |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> Enum.sort()

    assert kinds == [:callback, :function, :macro, :type] or
             kinds == [:callback, :function, :type]

    assert length(ctx.population) >= 100
    assert Enum.count(ctx.population, fn {_, _, _, _, d} -> d > 0 end) >= 20

    refute Enum.any?(ctx.population, fn {m, _, _, _, _} ->
             m in [BeamMCP.PublicAPI, BeamMCP.H2C]
           end)
  end

  @tag :tmp_dir
  test "the tree: the writer is idempotent on the committed baseline", %{tmp_dir: dir} do
    path = Path.join(dir, "public-api.txt")
    File.cp!(@baseline, path)
    assert {n, 0} = PublicAPI.write_baseline!(path)
    assert n == length(PublicAPI.read_baseline!(@baseline))
    assert File.read!(path) == File.read!(@baseline)
  end

  # ---- the population, on a fixture module ------------------------------------------------

  @fixture [Fixture.PublicAPI, Fixture.PublicAPI.Hidden]

  test "the population reads a real module: functions, defaults, a type, a callback; not @doc false, not a hidden module, and @deprecated seen" do
    population = PublicAPI.population(@fixture)

    assert Enum.sort(population) == [
             {Fixture.PublicAPI, :callback, :render, 1, 0},
             {Fixture.PublicAPI, :function, :defaulted, 3, 2},
             {Fixture.PublicAPI, :function, :old, 1, 0},
             {Fixture.PublicAPI, :function, :plain, 1, 0},
             {Fixture.PublicAPI, :macro, :twice, 1, 0},
             {Fixture.PublicAPI, :type, :shape, 0, 0}
           ]

    assert PublicAPI.deprecated(@fixture) == [{Fixture.PublicAPI, :function, :old, 1, 0}]
    refute Enum.any?(population, fn {m, _, _, _, _} -> m == Fixture.PublicAPI.Hidden end)
    refute Enum.any?(population, fn {_, _, name, _, _} -> name == :hidden end)
  end

  @tag :tmp_dir
  test "the writer, on the fixture: keeps every line and its markers, marks what the surface gained, lost or deprecated as Unreleased; the release step writes the number in",
       %{tmp_dir: dir} do
    path = Path.join(dir, "public-api.txt")

    File.write!(path, """
    # a header
    BeamMCP.Fixture.PublicAPI function plain/1
    BeamMCP.Fixture.PublicAPI function gone/1 deprecated_since=0.2.0 removed_in=0.5.0
    BeamMCP.Fixture.PublicAPI function vanished/3
    BeamMCP.Fixture.PublicAPI type shape/0
    """)

    {total, added} = PublicAPI.write_baseline!(path, modules: @fixture)
    lines = PublicAPI.read_baseline!(path)
    assert total == length(lines) and total == 8 and added == 4
    assert {{Fixture.PublicAPI, :macro, :twice, 1, 0}, %{"since" => "Unreleased"}} in lines

    # Kept as they were; the line for an entry no longer public marked, not dropped.
    assert {{Fixture.PublicAPI, :function, :gone, 1, 0},
            %{"deprecated_since" => "0.2.0", "removed_in" => "0.5.0"}} in lines

    assert {{Fixture.PublicAPI, :function, :vanished, 3, 0}, %{"removed_in" => "Unreleased"}} in lines
    assert {{Fixture.PublicAPI, :function, :plain, 1, 0}, %{}} in lines
    assert {{Fixture.PublicAPI, :type, :shape, 0, 0}, %{}} in lines
    # Gained: marked since; the defaults count part of the line; the deprecated one marked twice.
    assert {{Fixture.PublicAPI, :function, :defaulted, 3, 2}, %{"since" => "Unreleased"}} in lines
    assert {{Fixture.PublicAPI, :callback, :render, 1, 0}, %{"since" => "Unreleased"}} in lines

    assert {{Fixture.PublicAPI, :function, :old, 1, 0},
            %{"since" => "Unreleased", "deprecated_since" => "Unreleased"}} in lines

    assert File.read!(path) =~ "SPDX-License-Identifier"
    assert File.read!(path) =~ "defaulted/3 defaults=2 since=Unreleased"
    # A second write changes nothing.
    assert PublicAPI.write_baseline!(path, modules: @fixture) == {8, 0}

    # The release step: every Unreleased becomes the number, nothing else changes.
    assert PublicAPI.release_markers!("0.6.0", path) == 6
    after_release = PublicAPI.read_baseline!(path)

    assert {{Fixture.PublicAPI, :function, :vanished, 3, 0}, %{"removed_in" => "0.6.0"}} in after_release

    assert {{Fixture.PublicAPI, :function, :old, 1, 0},
            %{"since" => "0.6.0", "deprecated_since" => "0.6.0"}} in after_release

    refute File.read!(path) =~ "=Unreleased"
    assert PublicAPI.release_markers!("0.6.0", path) == 0
    assert_raise Version.InvalidVersionError, fn -> PublicAPI.release_markers!("0.6", path) end
  end

  @tag :tmp_dir
  test "the release step refuses a removal in a patch release, and on 1.x in a minor: the two rules the census cannot check",
       %{tmp_dir: dir} do
    path = Path.join(dir, "public-api.txt")
    removal = "# h\nBeamMCP.Fixture.PublicAPI function plain/1 removed_in=Unreleased\n"
    File.write!(path, removal)

    assert_raise ArgumentError, ~r/patch release carries no removal/, fn ->
      PublicAPI.release_markers!("0.6.1", path)
    end

    assert_raise ArgumentError, ~r/patch release carries no removal/, fn ->
      PublicAPI.release_markers!("1.0.1", path)
    end

    assert_raise ArgumentError, ~r/only in a major/, fn ->
      PublicAPI.release_markers!("1.1.0", path)
    end

    assert File.read!(path) == removal
    assert PublicAPI.release_markers!("0.6.0", path) == 1
    File.write!(path, removal)
    assert PublicAPI.release_markers!("2.0.0", path) == 1
    # A deprecation or an addition ships in a 1.x minor, or in any 0.x release (neither is a
    # break); on 1.x a patch fixes, so it refuses them too.
    step_one =
      "# h\nBeamMCP.Fixture.PublicAPI function plain/1 since=Unreleased deprecated_since=Unreleased\n"

    File.write!(path, step_one)
    assert PublicAPI.release_markers!("1.1.0", path) == 2
    File.write!(path, step_one)
    assert PublicAPI.release_markers!("0.6.1", path) == 2
    File.write!(path, step_one)

    assert_raise ArgumentError, ~r/a patch fixes/, fn ->
      PublicAPI.release_markers!("1.0.1", path)
    end

    assert File.read!(path) == step_one
  end

  # ---- the rule, on literal fixtures ------------------------------------------------------

  @m BeamMCP.Fixture.PublicAPI
  @plain {@m, :function, :plain, 1, 0}
  @old {@m, :function, :old, 1, 0}
  @shape {@m, :type, :shape, 0, 0}
  @render {@m, :callback, :render, 1, 0}

  defp lines(text) do
    for line <- String.split(text, "\n", trim: true), do: PublicAPI.parse_line!(line)
  end

  defp changelog(unreleased_body) do
    "# Changelog\n\n## [Unreleased]\n\n" <>
      unreleased_body <>
      "\n\n## [0.5.0] — 2026-09-16\n\n### Changed — BREAKING: old\n\n- old text.\n"
  end

  defp run(opts) do
    PublicAPI.violations(%{
      version: Keyword.get(opts, :version, "0.5.0"),
      population: Keyword.get(opts, :population, [@plain, @shape]),
      deprecated: Keyword.get(opts, :deprecated, []),
      lines: lines(Keyword.get(opts, :baseline, "#{@m} function plain/1\n#{@m} type shape/0")),
      sections:
        PublicAPI.sections(
          changelog(Keyword.get(opts, :changelog, "### Added\n\n- nothing named."))
        )
    })
  end

  defp checks(violations), do: violations |> Enum.map(&elem(&1, 0)) |> Enum.sort()

  test "the rule, green: a surface on the record has no violations" do
    assert run([]) == []
  end

  test "the rule: a public entry not in the baseline; a baseline line marked removed but still public" do
    assert checks(run(population: [@plain, @shape, @render])) == [:not_in_baseline]

    assert checks(run(baseline: "#{@m} function plain/1 removed_in=0.4.0\n#{@m} type shape/0")) ==
             [:marked_removed_but_public]
  end

  test "the rule: a deletion, a rename, an arity or defaults change, a docs-hidden flip -- each is a line gone unmarked" do
    # Deleted or hidden: the entry is absent from the population, its line unmarked.
    assert checks(run(population: [@shape])) == [:gone_unmarked]
    # Renamed, or arity/defaults changed: the old line gone unmarked AND the new entry unlisted.
    assert checks(run(population: [{@m, :function, :plain, 2, 1}, @shape])) == [
             :gone_unmarked,
             :not_in_baseline
           ]
  end

  test "the rule: an addition this cycle must be named -- the exact Module.name/arity, nothing looser" do
    baseline =
      "#{@m} function plain/1\n#{@m} type shape/0\n#{@m} callback render/1 since=Unreleased"

    pop = [@plain, @shape, @render]
    assert checks(run(population: pop, baseline: baseline)) == [:added_unnamed]

    assert checks(
             run(
               population: pop,
               baseline: baseline,
               changelog: "### Added\n\n- `render/1` arrives."
             )
           ) == [:added_unnamed]

    assert checks(
             run(
               population: pop,
               baseline: baseline,
               changelog: "### Added\n\n- `BeamMCP.Fixture.PublicAPI` gains a callback."
             )
           ) == [:added_unnamed]

    assert checks(
             run(
               population: pop,
               baseline: baseline,
               changelog: "### Added\n\n- `BeamMCP.Fixture.PublicAPI.render/12` arrives."
             )
           ) == [:added_unnamed]

    assert checks(
             run(
               population: pop,
               baseline: baseline,
               changelog: "### Added\n\n- `Other.BeamMCP.Fixture.PublicAPI.render/1` arrives."
             )
           ) == [:added_unnamed]

    assert run(
             population: pop,
             baseline: baseline,
             changelog: "### Added\n\n- `c:BeamMCP.Fixture.PublicAPI.render/1` arrives."
           ) == []

    assert run(
             population: pop,
             baseline: baseline,
             changelog:
               "### Added\n\n- **`BeamMCP.Fixture.PublicAPI.render/1`**, a callback\n  on a second line."
           ) == []

    # A released since= is history and asks for nothing.
    assert run(
             population: pop,
             baseline: String.replace(baseline, "since=Unreleased", "since=0.4.0")
           ) == []
  end

  test "the rule, step one: @deprecated and deprecated_since agree both ways, and this cycle's deprecation is what a bullet records" do
    pop = [@plain, @old, @shape]
    base = "#{@m} function plain/1\n#{@m} function old/1\n#{@m} type shape/0"

    marked =
      "#{@m} function plain/1\n#{@m} function old/1 deprecated_since=Unreleased\n#{@m} type shape/0"

    # The attribute without the marker; the marker without the attribute.
    assert checks(run(population: pop, deprecated: [@old], baseline: base)) == [
             :deprecated_unmarked
           ]

    assert checks(run(population: pop, deprecated: [], baseline: marked)) == [
             :deprecation_unrecorded,
             :marker_without_deprecated
           ]

    # Both, no bullet; both, a bullet that names it but does not say deprecated; both, recorded.
    assert checks(run(population: pop, deprecated: [@old], baseline: marked)) == [
             :deprecation_unrecorded
           ]

    assert checks(
             run(
               population: pop,
               deprecated: [@old],
               baseline: marked,
               changelog: "### Changed\n\n- `BeamMCP.Fixture.PublicAPI.old/1` is slower."
             )
           ) == [:deprecation_unrecorded]

    assert run(
             population: pop,
             deprecated: [@old],
             baseline: marked,
             changelog:
               "### Deprecated\n\n- `BeamMCP.Fixture.PublicAPI.old/1` is deprecated; use `plain/1`."
           ) == []

    # A released deprecated_since asks for no bullet.
    assert run(
             population: pop,
             deprecated: [@old],
             baseline: String.replace(marked, "Unreleased", "0.4.0")
           ) == []
  end

  test "the rule, removal: named, and either three minors of a RELEASED deprecated_since or the 0.x sentence under BREAKING with the how-to-tell sentence" do
    gone = fn markers -> "#{@m} function plain/1 #{markers}\n#{@m} type shape/0" end
    named = "### Removed\n\n- **Removed** `BeamMCP.Fixture.PublicAPI.plain/1`."

    breaking =
      "### Changed — BREAKING: plain/1 goes\n\n- **Removed** `BeamMCP.Fixture.PublicAPI.plain/1` — a 0.x documented break at the minor.\n  **How to tell whether you are affected:** you called it."

    # Silent; named but nothing else; named, first-time deprecated in the same change.
    assert checks(run(population: [@shape], baseline: gone.("removed_in=Unreleased"))) == [
             :removed_unnamed
           ]

    assert checks(
             run(population: [@shape], baseline: gone.("removed_in=Unreleased"), changelog: named)
           ) == [:removed_unjustified]

    assert checks(
             run(
               population: [@shape],
               baseline: gone.("deprecated_since=Unreleased removed_in=Unreleased"),
               changelog: named
             )
           ) == [:removed_unjustified]

    # Three minors: 0.3.0 shipped it, mix.exs reads 0.5.0 (0.3, 0.4, 0.5 shipped with the warning); 0.4.0 is two.
    assert run(
             population: [@shape],
             baseline: gone.("deprecated_since=0.3.0 removed_in=Unreleased"),
             changelog: named
           ) == []

    assert checks(
             run(
               population: [@shape],
               baseline: gone.("deprecated_since=0.4.0 removed_in=Unreleased"),
               changelog: named
             )
           ) == [:removed_unjustified]

    # The 0.x sentence: whole, or not at all.
    assert run(
             population: [@shape],
             baseline: gone.("removed_in=Unreleased"),
             changelog: breaking
           ) == []

    assert checks(
             run(
               population: [@shape],
               baseline: gone.("removed_in=Unreleased"),
               changelog: String.replace(breaking, "BREAKING: ", "")
             )
           ) == [:removed_unjustified]

    assert checks(
             run(
               population: [@shape],
               baseline: gone.("removed_in=Unreleased"),
               changelog:
                 String.replace(breaking, "How to tell whether you are affected", "How to know")
             )
           ) == [:breaking_without_how_to_tell, :removed_unjustified]

    assert checks(
             run(
               population: [@shape],
               baseline: gone.("removed_in=Unreleased"),
               changelog: String.replace(breaking, "documented break at the minor", "break")
             )
           ) == [:removed_unjustified]

    # The phrase on a bullet naming a different entry does not count for this one.
    other =
      "### Changed — BREAKING: shape goes\n\n- `t:BeamMCP.Fixture.PublicAPI.shape/0` — a 0.x documented break at the minor.\n- **Removed** `BeamMCP.Fixture.PublicAPI.plain/1`.\n  **How to tell whether you are affected:** you called it."

    assert checks(
             run(population: [@shape], baseline: gone.("removed_in=Unreleased"), changelog: other)
           ) == [:removed_unjustified]

    # On 1.x there is no 0.x sentence; three minors of the new major are the wait.
    assert checks(
             run(
               version: "1.0.0",
               population: [@shape],
               baseline: gone.("removed_in=Unreleased"),
               changelog: breaking
             )
           ) == [:removed_unjustified]

    assert checks(
             run(
               version: "1.0.0",
               population: [@shape],
               baseline: gone.("deprecated_since=0.7.0 removed_in=Unreleased"),
               changelog: named
             )
           ) == [:removed_unjustified]

    assert run(
             version: "1.3.0",
             population: [@shape],
             baseline: gone.("deprecated_since=0.7.0 removed_in=Unreleased"),
             changelog: named
           ) == []

    assert run(
             version: "1.4.0",
             population: [@shape],
             baseline: gone.("deprecated_since=1.2.0 removed_in=Unreleased"),
             changelog: named
           ) == []

    assert checks(
             run(
               version: "1.3.0",
               population: [@shape],
               baseline: gone.("deprecated_since=1.2.0 removed_in=Unreleased"),
               changelog: named
             )
           ) == [:removed_unjustified]

    # A released removed_in is history: the census asks nothing of it (the back-dating limit, said on the page).
    assert run(population: [@shape], baseline: gone.("removed_in=0.5.0")) == []
  end

  test "the rule: markers name a release no later than mix.exs's and parse; Unreleased markers need an Unreleased section" do
    assert checks(run(baseline: "#{@m} function plain/1 since=0.6.0\n#{@m} type shape/0")) == [
             :future_marker
           ]

    assert checks(run(baseline: "#{@m} function plain/1 since=0.5\n#{@m} type shape/0")) == [
             :unparsed_marker
           ]

    # Every kind of marker, not since= alone: a removal or a deprecation dated to a number that
    # has not shipped is the one back-date the census can see.
    assert checks(
             run(
               population: [@shape],
               baseline: "#{@m} function plain/1 removed_in=0.6.0\n#{@m} type shape/0"
             )
           ) == [:future_marker]

    assert checks(
             run(
               population: [@shape],
               baseline: "#{@m} function plain/1 removed_in=0.6\n#{@m} type shape/0"
             )
           ) == [:unparsed_marker]

    assert checks(
             run(
               population: [@plain, @shape],
               deprecated: [@plain],
               baseline: "#{@m} function plain/1 deprecated_since=0.6.0\n#{@m} type shape/0"
             )
           ) == [:future_marker]

    # An empty Unreleased section beside an Unreleased marker: the release skipped release_markers!/1.
    assert checks(
             run(
               baseline: "#{@m} function plain/1 since=Unreleased\n#{@m} type shape/0",
               changelog: ""
             )
           ) == [:added_unnamed, :unreleased_leftover]

    assert run(baseline: "#{@m} function plain/1 since=0.5.0\n#{@m} type shape/0", changelog: "") ==
             []
  end

  test "the rule: a BREAKING heading in the Unreleased section carries the how-to-tell sentence" do
    assert checks(run(changelog: "### Changed — BREAKING: something\n\n- a bullet.")) == [
             :breaking_without_how_to_tell
           ]

    assert run(
             changelog:
               "### Changed — BREAKING: something\n\n- a bullet. **How to tell whether you are affected:** thus."
           ) == []
  end

  test "sections/1 reads the Unreleased section only, heading by heading, bullet by bullet" do
    text =
      "# C\n\n## [Unreleased]\n\n### A\n\n- one\n  continued\n- two\n\n### B — BREAKING\n\nprose\n\n- three\n\n## [0.5.0]\n\n### Z\n\n- zed\n"

    assert [
             {"### A", _, ["- one\n  continued", "- two"]},
             {"### B — BREAKING", body, ["- three"]}
           ] = PublicAPI.sections(text)

    assert body =~ "prose"
    assert PublicAPI.sections("# C\n\n## [Unreleased]\n\n## [0.5.0]\n\n### Z\n\n- zed\n") == []
    assert_raise MatchError, fn -> PublicAPI.sections("# C\n\n## [0.5.0]\n") end
  end

  test "three minors before a removal: the arithmetic, at its edges" do
    # 0.6.0 shipped the deprecation; the removal ships in the release after mix.exs's.
    assert PublicAPI.removable?("0.6.0", "0.8.0")
    assert PublicAPI.removable?("0.6.0", "0.9.0")
    refute PublicAPI.removable?("0.6.0", "0.7.0")
    refute PublicAPI.removable?("0.6.0", "0.6.0")
    refute PublicAPI.removable?("0.6.0", "0.6.9")
    # Across a major: three minors of the new major ship with it first.
    refute PublicAPI.removable?("0.7.0", "1.0.0")
    refute PublicAPI.removable?("0.7.0", "1.2.0")
    assert PublicAPI.removable?("0.7.0", "1.3.0")
    # On 1.x: the same count on the same major (the release number is the release's).
    assert PublicAPI.removable?("1.2.0", "1.4.0")
    refute PublicAPI.removable?("1.2.0", "1.3.0")
    # Never on a lower major.
    refute PublicAPI.removable?("1.2.0", "0.9.0")
  end

  test "the baseline grammar: defaults, markers, and what it refuses" do
    assert {{BeamMCP.Cursor, :function, :decode, 2, 0}, %{}} =
             PublicAPI.parse_line!("BeamMCP.Cursor function decode/2")

    assert {{BeamMCP.Transport.Stdio, :function, :run, 1, 1}, %{"since" => "Unreleased"}} =
             PublicAPI.parse_line!(
               "BeamMCP.Transport.Stdio function run/1 defaults=1 since=Unreleased"
             )

    assert {{BeamMCP.Cursor, :type, :key, 0, 0}, %{"deprecated_since" => "0.6.0"}} =
             PublicAPI.parse_line!("BeamMCP.Cursor type key/0 deprecated_since=0.6.0")

    assert {{BeamMCP.Fixture.PublicAPI, :macro, :twice, 1, 0}, %{}} =
             PublicAPI.parse_line!("BeamMCP.Fixture.PublicAPI macro twice/1")

    assert_raise ArgumentError, ~r/unknown marker/, fn ->
      PublicAPI.parse_line!("BeamMCP.Cursor function decode/2 gone=0.5.0")
    end

    assert_raise ArgumentError, fn -> PublicAPI.parse_line!("BeamMCP.Cursor field decode/2") end
  end
end
