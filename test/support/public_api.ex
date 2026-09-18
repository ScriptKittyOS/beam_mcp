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
  # An ENTRY is `{module, kind, name, arity}` for every function, macro, callback or type that
  # ex_doc lists: the module's `@moduledoc` is not `false`, and the entry's `@doc` is not
  # `false`. A missing `@doc` is listed by ex_doc and is public here too -- hiding is explicit.
  #
  # A BASELINE LINE is `Module kind name/arity` followed by zero or more `key=value` markers:
  #   since=V              added while mix.exs read version V (checked against the CHANGELOG
  #                        while V is the current version; historic afterwards)
  #   deprecated_since=V   `@deprecated` first shipped while mix.exs read V
  #   removed_in=V         left the public surface while mix.exs read V -- a deletion, a
  #                        rename, an arity change or a `@doc false`; the line stays, so the
  #                        tree carries the record (a line deleted outright is invisible to a
  #                        tree-only census, and is a reviewer's line like any edited pin)
  # Lines are append-only in intent: an entry's line changes state, it does not vanish.

  @baseline "docs/public-api.txt"
  @kinds [:function, :macro, :callback, :type]

  @doc false
  def baseline_path, do: @baseline

  # The application's modules compiled from lib/ -- under MIX_ENV=test the application also
  # carries test/support (this module, the fixtures, the h2c client), which ship to nobody.
  @doc false
  def modules do
    {:ok, modules} = :application.get_key(:beam_mcp, :modules)

    for m <- Enum.sort(modules),
        source = to_string(m.module_info(:compile)[:source]),
        String.contains?(source, "/lib/"),
        do: m
  end

  @doc false
  @spec population() :: [{module(), atom(), atom(), non_neg_integer()}]
  def population do
    for m <- modules(),
        {:docs_v1, _, _, _, mdoc, _, entries} <- [Code.fetch_docs(m)],
        mdoc != :hidden,
        {{kind, name, arity}, _, _, doc, _} <- entries,
        kind in @kinds,
        doc != :hidden,
        do: {m, kind, name, arity}
  end

  @doc false
  @spec deprecated() :: [{module(), atom(), atom(), non_neg_integer()}]
  def deprecated do
    for m <- modules(),
        {:docs_v1, _, _, _, mdoc, _, entries} <- [Code.fetch_docs(m)],
        mdoc != :hidden,
        {{kind, name, arity}, _, _, doc, meta} <- entries,
        kind in @kinds,
        doc != :hidden,
        is_map(meta) and is_binary(meta[:deprecated]),
        do: {m, kind, name, arity}
  end

  @doc false
  def format({m, kind, name, arity}), do: "#{inspect(m)} #{kind} #{name}/#{arity}"

  # Three minors of deprecation before a removal on the same 0.x major -- `0.5.0` written,
  # removable when mix.exs reads `0.8.0` -- and on 1.x and later only the next major.
  @doc false
  @spec removable?(String.t(), String.t()) :: boolean()
  def removable?(deprecated_since, now) do
    since = Version.parse!(deprecated_since)
    now = Version.parse!(now)

    if now.major == 0 and since.major == 0,
      do: now.minor - since.minor >= 3,
      else: now.major > since.major
  end

  @doc false
  @spec read_baseline!(Path.t()) :: [{{module(), atom(), atom(), non_neg_integer()}, map()}]
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

    markers =
      Map.new(markers, fn marker ->
        case String.split(marker, "=", parts: 2) do
          [k, v] when k in ["since", "deprecated_since", "removed_in"] -> {k, v}
          _ -> raise ArgumentError, "unknown marker in #{inspect(line)}"
        end
      end)

    {{Module.concat([mod]), kind, String.to_atom(name), String.to_integer(arity)}, markers}
  end

  # `initial: true` writes the first baseline with no `since=` markers: those entries predate
  # the census and have no CHANGELOG line to be held to.
  @doc false
  def write_baseline!(path \\ @baseline, opts \\ []) do
    header = """
    # SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
    # SPDX-License-Identifier: Apache-2.0
    #
    # The public surface of beam_mcp, as ex_doc lists it: one line per function, macro,
    # callback or type, `Module kind name/arity`, with markers the census reads
    # (since=, deprecated_since=, removed_in=; see docs/api-stability.md). Written by
    # `mix run -e "BeamMCP.PublicAPI.write_baseline!()"`, which keeps every marker in place
    # and adds the lines the compiled application has gained; a line is never deleted, it
    # changes state. The census in test/beam_mcp/public_api_census_test.exs holds
    # the compiled application to this file and this file to the CHANGELOG.
    """

    existing = if File.exists?(path), do: Map.new(read_baseline!(path)), else: %{}
    version = Mix.Project.config()[:version]
    present = population()

    new_markers = if opts[:initial], do: %{}, else: %{"since" => version}

    added =
      for entry <- present, not Map.has_key?(existing, entry), do: {entry, new_markers}

    lines =
      (Map.to_list(existing) ++ added)
      |> Enum.sort_by(fn {{m, kind, name, arity}, _} -> {inspect(m), kind, name, arity} end)
      |> Enum.map(fn {entry, markers} ->
        suffix =
          for k <- ["since", "deprecated_since", "removed_in"], v = markers[k], do: " #{k}=#{v}"

        format(entry) <> Enum.join(suffix)
      end)

    File.write!(path, header <> Enum.join(lines, "\n") <> "\n")
    {length(lines), length(added)}
  end
end
