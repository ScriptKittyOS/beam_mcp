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
  # of the three-minor rule); an entry removed, renamed or with its arity changed must already
  # have been `@deprecated` for three minors, or the CHANGELOG entry must say it is a 0.x
  # documented break at the minor -- a first-time `@deprecated` in the same change does not
  # count; a docs-hidden flip is a removal. Each kind has its one condition set; there is no
  # OR between them.
  #
  # The record is read from the tree, never from git: a removed entry's baseline line stays,
  # marked `removed_in=V`, so the tree carries what left and when. A line deleted outright is
  # invisible to a tree-only census -- the same as deleting any pinned list -- and is a
  # reviewer's line, said here so nobody takes this census for more than it is.
  #
  # "The current version" is mix.exs's version at the time of the change: a marker whose
  # version equals it is this cycle's and is held to the Unreleased section; the release bump
  # makes it historic. Three minors: `deprecated_since=0.5.0` (written in the 0.5.0 cycle,
  # shipping in 0.6.0) is removable in a cycle whose version reads 0.8.0 or later (0.6, 0.7,
  # 0.8 shipped with the deprecation); on the 1.x line, at the next major only.
  use ExUnit.Case, async: true

  alias BeamMCP.PublicAPI

  @baseline PublicAPI.baseline_path()
  @break_phrase "documented break at the minor"

  setup_all do
    version = Mix.Project.config()[:version]
    baseline = PublicAPI.read_baseline!(@baseline)
    population = PublicAPI.population()
    deprecated = MapSet.new(PublicAPI.deprecated())

    {:ok,
     version: version,
     baseline: Map.new(baseline),
     lines: baseline,
     population: MapSet.new(population),
     deprecated: deprecated,
     unreleased: unreleased(File.read!("CHANGELOG.md"))}
  end

  # The Unreleased section's bullets: each `- ` bullet with its continuation lines, one string.
  defp unreleased(changelog) do
    [_, rest] = String.split(changelog, "\n## [Unreleased]", parts: 2)
    section = rest |> String.split(~r/\n## \[/, parts: 2) |> hd()

    section
    |> String.split(~r/\n(?=- )/)
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&String.starts_with?(&1, "- "))
  end

  # The CHANGELOG names an entry when a bullet carries the exact `Module.name/arity` (a type
  # or callback may be written with its `t:`/`c:` prefix); nothing looser -- not the name
  # alone, not the module alone.
  defp naming({m, _kind, name, arity}, bullets) do
    text = "#{inspect(m)}.#{name}/#{arity}"
    Enum.filter(bullets, &String.contains?(&1, text))
  end

  defp parse_version!(v) do
    case Version.parse(v) do
      {:ok, parsed} -> parsed
      :error -> flunk("a marker's version does not parse: #{inspect(v)}")
    end
  end

  test "the baseline file parses, and every entry it lists is one kind of the four", ctx do
    assert ctx.lines != []

    for {{m, kind, name, arity}, markers} <- ctx.lines do
      assert kind in [:function, :macro, :callback, :type]
      assert is_atom(m) and is_atom(name) and is_integer(arity)
      for {_, v} <- markers, do: parse_version!(v)
    end
  end

  test "every documented public entry is in the baseline and not marked removed", ctx do
    missing = for e <- ctx.population, not Map.has_key?(ctx.baseline, e), do: e

    assert missing == [],
           "public and not in #{@baseline} (write it with `MIX_ENV=test mix run -e " <>
             "\"BeamMCP.PublicAPI.write_baseline!()\"` and name each in the CHANGELOG):\n  " <>
             Enum.map_join(missing, "\n  ", &PublicAPI.format/1)

    still_public =
      for e <- ctx.population,
          markers = ctx.baseline[e],
          is_map(markers) and Map.has_key?(markers, "removed_in"),
          do: e

    assert still_public == [],
           "marked removed in #{@baseline} but still public:\n  " <>
             Enum.map_join(still_public, "\n  ", &PublicAPI.format/1)
  end

  test "every baseline entry not marked removed is still public: a deletion, a rename, an arity change or a docs-hidden flip must be marked removed_in and named",
       ctx do
    gone =
      for {e, markers} <- ctx.lines,
          not Map.has_key?(markers, "removed_in"),
          not MapSet.member?(ctx.population, e),
          do: e

    assert gone == [],
           "in #{@baseline} and gone from the public surface (mark the line removed_in=#{ctx.version} " <>
             "and name it in the CHANGELOG; a docs-hidden flip is a removal too):\n  " <>
             Enum.map_join(gone, "\n  ", &PublicAPI.format/1)
  end

  test "an entry added in this cycle is named in the CHANGELOG", ctx do
    unnamed =
      for {e, %{"since" => v}} <- ctx.lines,
          v == ctx.version,
          naming(e, ctx.unreleased) == [],
          do: e

    assert unnamed == [],
           "added (since=#{ctx.version}) and not named in the Unreleased section:\n  " <>
             Enum.map_join(unnamed, "\n  ", &PublicAPI.format/1)
  end

  test "@deprecated and deprecated_since agree, and this cycle's deprecations are what the CHANGELOG records",
       ctx do
    # The tree's two statements of a deprecation -- the attribute and the baseline marker --
    # must agree both ways: a `@deprecated` with no marker is an unrecorded step one; a marker
    # with no `@deprecated` is a record of something the code does not say.
    marked =
      for {e, %{"deprecated_since" => _}} <- ctx.lines,
          not Map.has_key?(ctx.baseline[e], "removed_in"),
          do: e

    attr_only = for e <- ctx.deprecated, e not in marked, do: e
    marker_only = for e <- marked, not MapSet.member?(ctx.deprecated, e), do: e

    assert attr_only == [],
           "@deprecated without deprecated_since in #{@baseline}:\n  " <>
             Enum.map_join(attr_only, "\n  ", &PublicAPI.format/1)

    assert marker_only == [],
           "deprecated_since in #{@baseline} without @deprecated on the code:\n  " <>
             Enum.map_join(marker_only, "\n  ", &PublicAPI.format/1)

    unrecorded =
      for {e, %{"deprecated_since" => v}} <- ctx.lines,
          v == ctx.version,
          not Enum.any?(naming(e, ctx.unreleased), &(&1 =~ ~r/deprecat/i)),
          do: e

    assert unrecorded == [],
           "deprecated this cycle and no Unreleased bullet names it as a deprecation:\n  " <>
             Enum.map_join(unrecorded, "\n  ", &PublicAPI.format/1)
  end

  test "an entry removed in this cycle is named in the CHANGELOG, and was deprecated for three minors or the entry says it is a 0.x documented break at the minor",
       ctx do
    removed =
      for {e, %{"removed_in" => v} = markers} <- ctx.lines, v == ctx.version, do: {e, markers}

    unnamed = for {e, _} <- removed, naming(e, ctx.unreleased) == [], do: e

    assert unnamed == [],
           "removed (removed_in=#{ctx.version}) and not named in the Unreleased section:\n  " <>
             Enum.map_join(unnamed, "\n  ", &PublicAPI.format/1)

    unjustified =
      for {e, markers} <- removed,
          naming(e, ctx.unreleased) != [],
          not (Map.has_key?(markers, "deprecated_since") and
                 PublicAPI.removable?(markers["deprecated_since"], ctx.version)),
          not (parse_version!(ctx.version).major == 0 and
                 Enum.any?(naming(e, ctx.unreleased), &String.contains?(&1, @break_phrase))),
          do: e

    assert unjustified == [],
           "removed this cycle with neither three minors of @deprecated behind it nor an " <>
             "Unreleased bullet saying \"#{@break_phrase}\":\n  " <>
             Enum.map_join(unjustified, "\n  ", &PublicAPI.format/1)
  end

  test "three minors on 0.x, the next major on 1.x: the arithmetic, at its edges" do
    # 0.5.0 written (ships in 0.6.0): 0.6, 0.7, 0.8 ship with the warning; removable at 0.8.0.
    assert PublicAPI.removable?("0.5.0", "0.8.0")
    assert PublicAPI.removable?("0.5.0", "0.9.0")
    refute PublicAPI.removable?("0.5.0", "0.7.0")
    refute PublicAPI.removable?("0.5.0", "0.5.0")
    refute PublicAPI.removable?("0.5.0", "0.5.9")
    # 1.x: minors do not count, only the major.
    refute PublicAPI.removable?("1.2.0", "1.9.0")
    assert PublicAPI.removable?("1.2.0", "2.0.0")
    # Deprecated on 0.x, removed on 1.x: the major changed, and that is the only 1.x rule.
    assert PublicAPI.removable?("0.7.0", "1.0.0")
  end

  test "the baseline grammar refuses what it does not know: an unknown kind, an unknown marker" do
    assert {{BeamMCP.Cursor, :function, :decode, 2}, %{}} =
             PublicAPI.parse_line!("BeamMCP.Cursor function decode/2")

    assert {{BeamMCP.Cursor, :type, :key, 0}, %{"deprecated_since" => "0.5.0"}} =
             PublicAPI.parse_line!("BeamMCP.Cursor type key/0 deprecated_since=0.5.0")

    assert_raise ArgumentError, ~r/unknown marker/, fn ->
      PublicAPI.parse_line!("BeamMCP.Cursor function decode/2 gone=0.5.0")
    end

    assert_raise ArgumentError, fn ->
      PublicAPI.parse_line!("BeamMCP.Cursor field decode/2")
    end
  end

  @tag :tmp_dir
  test "the writer keeps every line and its markers, and adds the surface's new entries with since=<version>",
       %{tmp_dir: dir} do
    # The writer is the one way the baseline changes; it must never drop a line -- a removed
    # entry's line is the record -- and it must mark what it adds as this cycle's.
    path = Path.join(dir, "public-api.txt")
    version = Mix.Project.config()[:version]

    File.write!(path, """
    # a header
    BeamMCP.Cursor function decode/2
    BeamMCP.Cursor function gone/1 deprecated_since=0.2.0 removed_in=0.5.0
    BeamMCP.Cursor type key/0 deprecated_since=0.4.0
    """)

    {total, added} = PublicAPI.write_baseline!(path)
    lines = PublicAPI.read_baseline!(path)
    assert total == length(lines)
    assert added == MapSet.size(MapSet.new(PublicAPI.population())) - 2

    assert {{BeamMCP.Cursor, :function, :gone, 1},
            %{"deprecated_since" => "0.2.0", "removed_in" => "0.5.0"}} in lines

    assert {{BeamMCP.Cursor, :type, :key, 0}, %{"deprecated_since" => "0.4.0"}} in lines
    assert {{BeamMCP.Cursor, :function, :decode, 2}, %{}} in lines
    assert {{BeamMCP.Cursor, :function, :encode, 2}, %{"since" => version}} in lines
    assert File.read!(path) =~ "SPDX-License-Identifier"
  end

  test "the population is the four kinds ex_doc lists, from lib/ only, and it is not small",
       ctx do
    kinds = ctx.population |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> Enum.sort()

    assert kinds == [:callback, :function, :macro, :type] or
             kinds == [:callback, :function, :type]

    assert MapSet.size(ctx.population) >= 100
    refute Enum.any?(ctx.population, fn {m, _, _, _} -> m in [BeamMCP.PublicAPI, BeamMCP.H2C] end)
  end
end
