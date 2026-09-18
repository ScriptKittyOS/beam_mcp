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
  # marked `removed_in=R`, so the tree carries what left and when. A line deleted outright is
  # invisible to a tree-only census -- the same as deleting any pinned list -- and is a
  # reviewer's line, said here so nobody takes this census for more than it is.
  #
  # A marker's R is the release that ships the change, or the word `Unreleased` while the
  # change waits in the CHANGELOG's Unreleased section; the release writes its number in
  # (`BeamMCP.PublicAPI.release_markers!/1`). This cycle's markers are the `Unreleased` ones,
  # and they are held to the Unreleased section; a leftover `Unreleased` beside an empty
  # Unreleased section is a release that skipped that step. Three minors:
  # `deprecated_since=0.6.0` is removable once mix.exs -- the latest release -- reads 0.8.0
  # (0.6, 0.7 and 0.8 shipped with the warning; the removal ships in 0.9.0); across a major,
  # three minors of the new major (mix.exs at 1.3.0). The release NUMBER a removal ships under
  # (a minor on 0.x, a major from 1.0.0) is the release's to set and is not checked here.
  use ExUnit.Case, async: true

  alias BeamMCP.PublicAPI

  @baseline PublicAPI.baseline_path()
  @unreleased PublicAPI.unreleased()
  @break_phrase "documented break at the minor"
  @how_to_tell "How to tell whether you are affected"

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
     sections: unreleased(File.read!("CHANGELOG.md"))}
  end

  # The Unreleased section as `{heading, bullets}` per `### ` heading: each bullet is one
  # `- ` item with its continuation lines, one string.
  defp unreleased(changelog) do
    [_, rest] = String.split(changelog, "\n## [Unreleased]", parts: 2)
    section = rest |> String.split(~r/\n## \[/, parts: 2) |> hd()

    section
    |> String.split(~r/\n(?=### )/)
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&String.starts_with?(&1, "### "))
    |> Enum.map(fn block ->
      [heading | body] = String.split(block, "\n", parts: 2)
      body = Enum.join(body, "")

      bullets =
        body
        |> String.split(~r/\n(?=- )/)
        |> Enum.map(&String.trim/1)
        |> Enum.filter(&String.starts_with?(&1, "- "))

      {heading, body, bullets}
    end)
  end

  # The CHANGELOG names an entry when a bullet carries the exact `Module.name/arity` (a type
  # or callback may be written with its `t:`/`c:` prefix; a defaults count is not part of the
  # name), the arity ending there -- `Foo.bar/1` is not named by `Foo.bar/12`. Nothing
  # looser: not the name alone, not the module alone. Returns `{heading, body, bullet}`.
  defp naming({m, _kind, name, arity, _defaults}, sections) do
    pattern = ~r/#{Regex.escape("#{inspect(m)}.#{name}/#{arity}")}(?!\d)/

    for {heading, body, bullets} <- sections,
        bullet <- bullets,
        bullet =~ pattern,
        do: {heading, body, bullet}
  end

  defp parse_version!(v) do
    case Version.parse(v) do
      {:ok, parsed} -> parsed
      :error -> flunk("a marker's version does not parse: #{inspect(v)}")
    end
  end

  defp this_cycle?(v), do: v == @unreleased

  test "the baseline file parses: four kinds, a defaults count, markers that are a release or Unreleased",
       ctx do
    assert ctx.lines != []

    for {{m, kind, name, arity, defaults}, markers} <- ctx.lines do
      assert kind in [:function, :macro, :callback, :type]
      assert is_atom(m) and is_atom(name) and is_integer(arity) and is_integer(defaults)
      for {_, v} <- markers, not this_cycle?(v), do: parse_version!(v)
    end
  end

  test "a released marker names a release no later than mix.exs's, and Unreleased markers exist only while the Unreleased section has content",
       ctx do
    now = parse_version!(ctx.version)

    future =
      for {e, markers} <- ctx.lines,
          {k, v} <- markers,
          not this_cycle?(v),
          Version.compare(parse_version!(v), now) == :gt,
          do: "#{PublicAPI.format(e)} #{k}=#{v}"

    assert future == [],
           "markers naming a release after #{ctx.version}:\n  " <> Enum.join(future, "\n  ")

    pending =
      for {e, markers} <- ctx.lines,
          {k, v} <- markers,
          this_cycle?(v),
          do: "#{PublicAPI.format(e)} #{k}"

    if ctx.sections == [] do
      assert pending == [],
             "Unreleased markers with an empty Unreleased section -- the release did not run " <>
               "BeamMCP.PublicAPI.release_markers!/1:\n  " <> Enum.join(pending, "\n  ")
    end
  end

  test "every documented public entry is in the baseline and not marked removed", ctx do
    missing = for e <- ctx.population, not Map.has_key?(ctx.baseline, e), do: e

    assert missing == [],
           "public and not in #{@baseline} -- a new entry, or one whose arity or defaults " <>
             "changed (write the file with `MIX_ENV=test mix run -e " <>
             "\"BeamMCP.PublicAPI.write_baseline!()\"` and name each in the CHANGELOG):\n  " <>
             Enum.map_join(missing, "\n  ", &PublicAPI.format/1)

    still_public =
      for e <- ctx.population,
          markers = ctx.baseline[e],
          is_map(markers) and Map.has_key?(markers, "removed_in"),
          do: e

    assert still_public == [],
           "marked removed in #{@baseline} but still public (an entry that comes back: delete " <>
             "its removed_in, set since=#{@unreleased}, name it):\n  " <>
             Enum.map_join(still_public, "\n  ", &PublicAPI.format/1)
  end

  test "every baseline entry not marked removed is still public: a deletion, a rename, an arity or defaults change or a docs-hidden flip must be marked removed_in and named",
       ctx do
    gone =
      for {e, markers} <- ctx.lines,
          not Map.has_key?(markers, "removed_in"),
          not MapSet.member?(ctx.population, e),
          do: e

    assert gone == [],
           "in #{@baseline} and gone from the public surface (the writer marks the line " <>
             "removed_in=#{@unreleased}; name it in the CHANGELOG; a docs-hidden flip is a " <>
             "removal too):\n  " <> Enum.map_join(gone, "\n  ", &PublicAPI.format/1)
  end

  test "an entry added in this cycle is named in the CHANGELOG", ctx do
    unnamed =
      for {e, %{"since" => v}} <- ctx.lines,
          this_cycle?(v),
          naming(e, ctx.sections) == [],
          do: e

    assert unnamed == [],
           "added (since=#{@unreleased}) and not named in the Unreleased section:\n  " <>
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
           "@deprecated without deprecated_since in #{@baseline} (the writer adds it):\n  " <>
             Enum.map_join(attr_only, "\n  ", &PublicAPI.format/1)

    assert marker_only == [],
           "deprecated_since in #{@baseline} without @deprecated on the code:\n  " <>
             Enum.map_join(marker_only, "\n  ", &PublicAPI.format/1)

    unrecorded =
      for {e, %{"deprecated_since" => v}} <- ctx.lines,
          this_cycle?(v),
          not Enum.any?(naming(e, ctx.sections), fn {_, _, bullet} -> bullet =~ ~r/deprecat/i end),
          do: e

    assert unrecorded == [],
           "deprecated this cycle and no Unreleased bullet names it as a deprecation:\n  " <>
             Enum.map_join(unrecorded, "\n  ", &PublicAPI.format/1)
  end

  test "an entry removed in this cycle is named in the CHANGELOG, and was deprecated for three minors or the bullet says it is a 0.x documented break at the minor, under a BREAKING heading with the how-to-tell sentence",
       ctx do
    removed =
      for {e, %{"removed_in" => v} = markers} <- ctx.lines, this_cycle?(v), do: {e, markers}

    unnamed = for {e, _} <- removed, naming(e, ctx.sections) == [], do: e

    assert unnamed == [],
           "removed (removed_in=#{@unreleased}) and not named in the Unreleased section:\n  " <>
             Enum.map_join(unnamed, "\n  ", &PublicAPI.format/1)

    # The 0.x skip: the bullet says the phrase, sits under a `### ... BREAKING` heading, and
    # that section carries the how-to-tell sentence the README promises for every break.
    documented_break? = fn e ->
      parse_version!(ctx.version).major == 0 and
        Enum.any?(naming(e, ctx.sections), fn {heading, body, bullet} ->
          String.contains?(bullet, @break_phrase) and String.contains?(heading, "BREAKING") and
            String.contains?(body, @how_to_tell)
        end)
    end

    unjustified =
      for {e, markers} <- removed,
          naming(e, ctx.sections) != [],
          not (Map.has_key?(markers, "deprecated_since") and
                 not this_cycle?(markers["deprecated_since"]) and
                 PublicAPI.removable?(markers["deprecated_since"], ctx.version)),
          not documented_break?.(e),
          do: e

    assert unjustified == [],
           "removed this cycle with neither three minors of @deprecated behind it nor an " <>
             "Unreleased bullet saying \"#{@break_phrase}\" under a BREAKING heading with " <>
             "\"#{@how_to_tell}\":\n  " <> Enum.map_join(unjustified, "\n  ", &PublicAPI.format/1)
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

    assert_raise ArgumentError, ~r/unknown marker/, fn ->
      PublicAPI.parse_line!("BeamMCP.Cursor function decode/2 gone=0.5.0")
    end

    assert_raise ArgumentError, fn ->
      PublicAPI.parse_line!("BeamMCP.Cursor field decode/2")
    end
  end

  @tag :tmp_dir
  test "the writer keeps every line and its markers, marks what the surface gained, lost or deprecated as Unreleased, and the release step writes the number in",
       %{tmp_dir: dir} do
    path = Path.join(dir, "public-api.txt")

    File.write!(path, """
    # a header
    BeamMCP.Cursor function decode/2
    BeamMCP.Cursor function gone/1 deprecated_since=0.2.0 removed_in=0.5.0
    BeamMCP.Cursor function vanished/3
    BeamMCP.Cursor type key/0 deprecated_since=0.4.0
    """)

    {total, added} = PublicAPI.write_baseline!(path)
    lines = PublicAPI.read_baseline!(path)
    assert total == length(lines)
    assert added == MapSet.size(MapSet.new(PublicAPI.population())) - 2

    # Kept as they were; the line for an entry no longer public marked, not dropped.
    assert {{BeamMCP.Cursor, :function, :gone, 1, 0},
            %{"deprecated_since" => "0.2.0", "removed_in" => "0.5.0"}} in lines

    assert {{BeamMCP.Cursor, :function, :vanished, 3, 0}, %{"removed_in" => "Unreleased"}} in lines
    assert {{BeamMCP.Cursor, :type, :key, 0, 0}, %{"deprecated_since" => "0.4.0"}} in lines
    assert {{BeamMCP.Cursor, :function, :decode, 2, 0}, %{}} in lines
    assert {{BeamMCP.Cursor, :function, :encode, 2, 0}, %{"since" => "Unreleased"}} in lines
    # A default argument is part of the entry.
    assert {{BeamMCP.Transport.Stdio, :function, :run, 1, 1}, %{"since" => "Unreleased"}} in lines
    assert File.read!(path) =~ "SPDX-License-Identifier"

    # The release step: every Unreleased becomes the number, nothing else changes.
    n = PublicAPI.release_markers!("0.6.0", path)
    assert n == added + 1
    after_release = PublicAPI.read_baseline!(path)

    assert {{BeamMCP.Cursor, :function, :vanished, 3, 0}, %{"removed_in" => "0.6.0"}} in after_release

    assert {{BeamMCP.Cursor, :function, :encode, 2, 0}, %{"since" => "0.6.0"}} in after_release
    refute File.read!(path) =~ "=Unreleased"
    assert PublicAPI.release_markers!("0.6.0", path) == 0
  end

  test "the population is the four kinds ex_doc lists, from lib/ only, with defaults counted, and it is not small",
       ctx do
    kinds = ctx.population |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> Enum.sort()

    assert kinds == [:callback, :function, :macro, :type] or
             kinds == [:callback, :function, :type]

    assert MapSet.size(ctx.population) >= 100
    assert Enum.count(ctx.population, fn {_, _, _, _, d} -> d > 0 end) >= 20

    refute Enum.any?(ctx.population, fn {m, _, _, _, _} ->
             m in [BeamMCP.PublicAPI, BeamMCP.H2C]
           end)
  end

  test "a BREAKING heading in the Unreleased section carries the how-to-tell sentence", ctx do
    missing =
      for {heading, body, _} <- ctx.sections,
          String.contains?(heading, "BREAKING"),
          not String.contains?(body, @how_to_tell),
          do: heading

    assert missing == [],
           "BREAKING without \"#{@how_to_tell}\":\n  " <> Enum.join(missing, "\n  ")
  end
end
