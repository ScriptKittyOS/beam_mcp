# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.PublicAPI do
  @moduledoc false
  # The public surface, read from the compiled application's documentation chunks, and the
  # baseline file that pins it (`docs/public-api.txt`). Test support, not `lib/` (it reads
  # `Mix.Project`, which the population census bars from the package): a consumer reads the
  # baseline and `docs/api-stability.md`; this module is what the census test and
  # `MIX_ENV=test mix run -e "BeamMCP.PublicAPI.write_baseline!()"` share, so the population
  # and the file's grammar have one definition and the baseline is written by a command,
  # never by hand.
  #
  # An ENTRY is `{module, kind, name, arity, defaults}` for every function, macro, callback
  # or type that ex_doc lists: the module's `@moduledoc` is not `false`, and the entry's `@doc`
  # is not `false`. A missing `@doc` is listed by ex_doc and is public here too -- hiding is
  # explicit (and `@impl` is one way of hiding: it marks the callback `@doc false` unless
  # `@doc` is set). `defaults` is the number of default arguments, from the chunk: a function
  # `run(opts \\ [])` is `run/1 defaults=1` and is callable as `run/0` too, so dropping the
  # default removes a callable arity and changes the entry (a lane found the arity alone
  # blind to it).
  #
  # A BASELINE LINE is `Module kind name/arity [defaults=N]` followed by markers:
  #   since=R              first shipped in release R
  #   deprecated_since=R   `@deprecated` first shipped in release R
  #   removed_in=R         left the public surface in release R -- a deletion, a rename, an
  #                        arity or defaults change, or a `@doc false`; the line stays, so the
  #                        tree carries the record (a line deleted outright is invisible to a
  #                        tree-only census, and is a reviewer's line like any edited pin)
  # R is a release number or the word `Unreleased` while the change waits in the CHANGELOG's
  # Unreleased section; the release that ships it writes its number in place of the word
  # (`release_markers!/1`). The census holds `Unreleased` markers to the Unreleased section
  # and refuses a leftover `Unreleased` once that section is empty. Lines are append-only in
  # intent: an entry's line changes state, it does not vanish -- with one exception, an entry
  # that comes back after a removal, whose `removed_in` is deleted and `since` set again.

  @baseline "docs/public-api.txt"
  @kinds [:function, :macro, :callback, :type]
  @unreleased "Unreleased"

  @type entry :: {module(), atom(), atom(), non_neg_integer(), non_neg_integer()}

  @doc false
  def baseline_path, do: @baseline

  @doc false
  def unreleased, do: @unreleased

  # The application's modules compiled from lib/ -- under MIX_ENV=test the application also
  # carries test/support (this module, the fixtures, the h2c client), which ship to nobody.
  # By the source path's prefix, the repository's own lib/ directory: a substring test on
  # "/lib/" read every test/support module as lib/ under a clone path that carried "/lib/"
  # (a lane measured `/var/lib/jenkins/...`) -- a false red, but a red for a right tree.
  @doc false
  def modules do
    {:ok, modules} = :application.get_key(:beam_mcp, :modules)
    lib = Path.expand("lib") <> "/"

    for m <- Enum.sort(modules),
        source = to_string(m.module_info(:compile)[:source]),
        String.starts_with?(source, lib),
        do: m
  end

  @doc false
  @spec population([module()]) :: [entry()]
  def population(modules \\ modules()) do
    for {entry, _meta} <- listed(modules), do: entry
  end

  @doc false
  @spec deprecated([module()]) :: [entry()]
  def deprecated(modules \\ modules()) do
    for {entry, meta} <- listed(modules), is_binary(meta[:deprecated]), do: entry
  end

  defp listed(modules) do
    for m <- modules,
        {:docs_v1, _, _, _, mdoc, _, entries} <- [Code.fetch_docs(m)],
        mdoc != :hidden,
        {{kind, name, arity}, _, _, doc, meta} <- entries,
        kind in @kinds,
        doc != :hidden,
        meta = if(is_map(meta), do: meta, else: %{}),
        do: {{m, kind, name, arity, meta[:defaults] || 0}, meta}
  end

  @doc false
  def format({m, kind, name, arity, defaults}) do
    "#{inspect(m)} #{kind} #{name}/#{arity}" <>
      if(defaults > 0, do: " defaults=#{defaults}", else: "")
  end

  # Three minor releases must ship with the deprecation before the release that removes the
  # entry: `deprecated_since` is the release that first shipped it and `now` is mix.exs's
  # version, the latest release, so the removal ships in the next one at the earliest --
  # `0.6.0` deprecated, removable once mix.exs reads `0.8.0` (0.6, 0.7 and 0.8 shipped with
  # the warning; the removal ships in 0.9.0). Across a major -- deprecated on 0.x, still
  # present at 1.0.0 -- three minors of the new major must ship with it (mix.exs at `1.3.0`
  # or later): an entry on the 1.0.0 surface waits like any 1.x entry. Never on a lower major.
  @doc false
  @spec removable?(String.t(), String.t()) :: boolean()
  def removable?(deprecated_since, now) do
    since = Version.parse!(deprecated_since)
    now = Version.parse!(now)

    cond do
      now.major < since.major -> false
      now.major == since.major -> now.minor - since.minor >= 2
      true -> now.minor >= 3
    end
  end

  @doc false
  @spec read_baseline!(Path.t()) :: [{entry(), map()}]
  def read_baseline!(path \\ @baseline) do
    for line <- File.read!(path) |> String.split("\n", trim: true),
        not String.starts_with?(line, "#") do
      parse_line!(line)
    end
  end

  @doc false
  def parse_line!(line) do
    [mod, kind, name_arity | markers] = String.split(line, " ", trim: true)
    [name, arity] = String.split(name_arity, "/")
    kind = String.to_existing_atom(kind)
    kind in @kinds || raise ArgumentError, "unknown kind in #{inspect(line)}"

    {defaults, markers} =
      case markers do
        ["defaults=" <> n | rest] -> {String.to_integer(n), rest}
        rest -> {0, rest}
      end

    markers =
      Map.new(markers, fn marker ->
        case String.split(marker, "=", parts: 2) do
          [k, v] when k in ["since", "deprecated_since", "removed_in"] -> {k, v}
          _ -> raise ArgumentError, "unknown marker in #{inspect(line)}"
        end
      end)

    {{Module.concat([mod]), kind, String.to_atom(name), String.to_integer(arity), defaults},
     markers}
  end

  # Writes the baseline from the compiled application and the file as it stands: a new
  # public entry gets `since=Unreleased`; an entry now `@deprecated` and not yet marked gets
  # `deprecated_since=Unreleased`; a line whose entry is no longer public and not yet marked
  # gets `removed_in=Unreleased`; every existing marker stays. `initial: true` writes the
  # first baseline with no markers at all -- those entries predate the census and have no
  # CHANGELOG line to be held to.
  @doc false
  def write_baseline!(path \\ @baseline, opts \\ []) do
    modules = Keyword.get(opts, :modules, modules())

    header = """
    # SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
    # SPDX-License-Identifier: Apache-2.0
    #
    # The public surface of beam_mcp, as ex_doc lists it: one line per function, macro,
    # callback or type, `Module kind name/arity [defaults=N]`, with markers the census reads
    # (since=, deprecated_since=, removed_in=; a release number, or `Unreleased` until the
    # release that ships the change writes its number in; see docs/api-stability.md).
    # Written by `MIX_ENV=test mix run -e "BeamMCP.PublicAPI.write_baseline!()"`, which keeps
    # every marker in place, marks what the compiled application has gained, deprecated or
    # lost, and never deletes a line. The census in test/beam_mcp/public_api_census_test.exs
    # holds the compiled application to this file and this file to the CHANGELOG.
    """

    existing = if File.exists?(path), do: Map.new(read_baseline!(path)), else: %{}
    present = MapSet.new(population(modules))
    deprecated = MapSet.new(deprecated(modules))
    initial = opts[:initial] == true

    marked =
      for {entry, markers} <- existing,
          do: {entry, mark(entry, markers, present, deprecated, initial)}

    added =
      for entry <- present, not Map.has_key?(existing, entry) do
        {entry,
         mark(entry, %{}, present, deprecated, initial)
         |> Map.merge(if(initial, do: %{}, else: %{"since" => @unreleased}))}
      end

    lines =
      (marked ++ added)
      |> Enum.sort_by(fn {{m, kind, name, arity, d}, _} -> {inspect(m), kind, name, arity, d} end)
      |> Enum.map(fn {entry, markers} ->
        suffix =
          for k <- ["since", "deprecated_since", "removed_in"], v = markers[k], do: " #{k}=#{v}"

        format(entry) <> Enum.join(suffix)
      end)

    File.write!(path, header <> Enum.join(lines, "\n") <> "\n")
    {length(lines), length(added)}
  end

  # What this write adds to a line's markers: `removed_in` for an entry no longer public,
  # `deprecated_since` for one now `@deprecated`; nothing on the initial write, and nothing
  # already marked is marked twice.
  defp mark(_entry, markers, _present, _deprecated, true), do: markers

  defp mark(entry, markers, present, deprecated, false) do
    cond do
      not MapSet.member?(present, entry) and not Map.has_key?(markers, "removed_in") ->
        Map.put(markers, "removed_in", @unreleased)

      MapSet.member?(deprecated, entry) and not Map.has_key?(markers, "deprecated_since") ->
        Map.put(markers, "deprecated_since", @unreleased)

      true ->
        markers
    end
  end

  # THE RULE, as one pure function over what the tree says, so the census test runs it on
  # the tree and a unit test runs it on literal fixtures -- a lane found every rule path
  # vacuous on a tree with no deprecation, no hidden module and no Unreleased marker, six of
  # seven mutants surviving, one of them switching the census off. `input` carries
  # `population` and `deprecated` (entries), `lines` (the baseline as read), `sections` (the
  # CHANGELOG's Unreleased section as `sections/1` returns it) and `version` (mix.exs's).
  # Returns `[]` when the surface is on the record, else `{check, entry_or_text}` tuples, one
  # per violation, with `check` naming the rule that failed.
  @break_phrase "documented break at the minor"
  @how_to_tell "How to tell whether you are affected"

  @doc false
  def break_phrase, do: @break_phrase
  @doc false
  def how_to_tell, do: @how_to_tell

  @doc false
  def violations(input) do
    ctx = %{
      population: MapSet.new(input.population),
      deprecated: MapSet.new(input.deprecated),
      lines: input.lines,
      baseline: Map.new(input.lines),
      sections: input.sections,
      version: input.version,
      now: Version.parse!(input.version)
    }

    List.flatten([
      marker_violations(ctx),
      surface_violations(ctx),
      addition_violations(ctx),
      deprecation_violations(ctx),
      removal_violations(ctx),
      heading_violations(ctx)
    ])
  end

  # Markers parse and name no release after mix.exs's; an Unreleased marker needs an
  # Unreleased section with content (else the release skipped `release_markers!/1`).
  defp marker_violations(ctx) do
    released =
      for {e, markers} <- ctx.lines,
          {k, v} <- markers,
          not this_cycle?(v),
          do: released_marker(e, k, v, ctx.now)

    leftover =
      for {e, markers} <- ctx.lines,
          {k, v} <- markers,
          ctx.sections == [] and this_cycle?(v),
          do: {:unreleased_leftover, "#{format(e)} #{k}"}

    [released, leftover]
  end

  defp released_marker(e, k, v, now) do
    case Version.parse(v) do
      {:ok, parsed} ->
        if Version.compare(parsed, now) == :gt,
          do: [{:future_marker, "#{format(e)} #{k}=#{v}"}],
          else: []

      :error ->
        [{:unparsed_marker, "#{format(e)} #{k}=#{v}"}]
    end
  end

  # The compiled application and the baseline agree: every public entry has an unremoved
  # line; every unremoved line has a public entry.
  defp surface_violations(ctx) do
    missing =
      for e <- ctx.population, not Map.has_key?(ctx.baseline, e), do: {:not_in_baseline, e}

    still_public =
      for e <- ctx.population,
          markers = ctx.baseline[e],
          is_map(markers) and Map.has_key?(markers, "removed_in"),
          do: {:marked_removed_but_public, e}

    gone =
      for {e, markers} <- ctx.lines,
          not Map.has_key?(markers, "removed_in"),
          not MapSet.member?(ctx.population, e),
          do: {:gone_unmarked, e}

    [missing, still_public, gone]
  end

  defp addition_violations(ctx) do
    for {e, %{"since" => v}} <- ctx.lines,
        this_cycle?(v),
        naming(e, ctx.sections) == [],
        do: {:added_unnamed, e}
  end

  # The attribute and the marker agree both ways; this cycle's deprecation is what a bullet
  # records (a removed entry's deprecation is the removal check's business).
  defp deprecation_violations(ctx) do
    marked =
      for {e, %{"deprecated_since" => _}} <- ctx.lines,
          not Map.has_key?(ctx.baseline[e], "removed_in"),
          do: e

    attr_only = for e <- ctx.deprecated, e not in marked, do: {:deprecated_unmarked, e}

    marker_only =
      for e <- marked, not MapSet.member?(ctx.deprecated, e), do: {:marker_without_deprecated, e}

    unrecorded =
      for {e, %{"deprecated_since" => v} = markers} <- ctx.lines,
          this_cycle?(v),
          not Map.has_key?(markers, "removed_in"),
          not Enum.any?(naming(e, ctx.sections), fn {_, _, bullet} -> bullet =~ ~r/deprecat/i end),
          do: {:deprecation_unrecorded, e}

    [attr_only, marker_only, unrecorded]
  end

  # This cycle's removals: named, and either three minors of a released deprecation or the
  # 0.x sentence, whole.
  defp removal_violations(ctx) do
    removed =
      for {e, %{"removed_in" => v} = markers} <- ctx.lines, this_cycle?(v), do: {e, markers}

    unnamed = for {e, _} <- removed, naming(e, ctx.sections) == [], do: {:removed_unnamed, e}

    unjustified =
      for {e, markers} <- removed,
          naming(e, ctx.sections) != [],
          not waited?(markers, ctx.version),
          not documented_break?(e, ctx.sections, ctx.now),
          do: {:removed_unjustified, e}

    [unnamed, unjustified]
  end

  defp heading_violations(ctx) do
    for {heading, body, _} <- ctx.sections,
        String.contains?(heading, "BREAKING"),
        not String.contains?(body, @how_to_tell),
        do: {:breaking_without_how_to_tell, heading}
  end

  # This cycle's marker: the word, not a release number.
  defp this_cycle?(v), do: v == @unreleased

  # Three minors of @deprecated on the tree, the marker naming a RELEASE (an Unreleased
  # deprecation in the same change is no wait).
  defp waited?(markers, version) do
    case markers do
      %{"deprecated_since" => since} when since != @unreleased -> removable?(since, version)
      _ -> false
    end
  end

  # The 0.x skip: mix.exs's major is 0, and a bullet naming the entry carries the phrase,
  # under a heading that says BREAKING, in a section that carries the how-to-tell sentence.
  defp documented_break?(e, sections, now) do
    now.major == 0 and
      Enum.any?(naming(e, sections), fn {heading, body, bullet} ->
        String.contains?(bullet, @break_phrase) and String.contains?(heading, "BREAKING") and
          String.contains?(body, @how_to_tell)
      end)
  end

  # The CHANGELOG's Unreleased section as `{heading, body, bullets}` per `### ` heading; each
  # bullet is one `- ` item with its continuation lines, one string. No Unreleased heading at
  # all is a CHANGELOG this census does not know how to read: raise, loudly.
  @doc false
  def sections(changelog) do
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
  # name), the name starting and the arity ending there -- `Foo.bar/1` is not named by
  # `Foo.bar/12` nor by `Other.Foo.bar/1`. Nothing looser: not the name alone, not the module
  # alone. Returns `{heading, body, bullet}` per naming bullet.
  @doc false
  def naming({m, _kind, name, arity, _defaults}, sections) do
    pattern = ~r/(?<![\w.])#{Regex.escape("#{inspect(m)}.#{name}/#{arity}")}(?!\d)/

    for {heading, body, bullets} <- sections,
        bullet <- bullets,
        bullet =~ pattern,
        do: {heading, body, bullet}
  end

  # The release step: every `Unreleased` marker becomes the release's number. Returns how
  # many it wrote.
  @doc false
  def release_markers!(version, path \\ @baseline) do
    _ = Version.parse!(version)
    text = File.read!(path)
    {new, n} = replace_unreleased(text, version)
    File.write!(path, new)
    n
  end

  defp replace_unreleased(text, version) do
    pattern = ~r/=(#{@unreleased})\b/
    count = length(Regex.scan(pattern, text))
    {Regex.replace(pattern, text, "=" <> version), count}
  end
end
