# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.ReadmeSplitCensusTest do
  @moduledoc """
  The README's four-way split -- shipping now / decided and not built / scheduled / deliberately
  out -- held to the tree by census rather than by reading.

  The population is derived from the README: the section "What this package is, and is not"
  is cut into its four paragraphs by their bold leads, and every `BeamMCP.…` name in backticks
  in each paragraph is a claim about the tree -- the bare name, a struct literal
  (`%BeamMCP.X{}`), a function or callback reference (`BeamMCP.X.f/1`), with or without an
  `Elixir.` prefix; a name outside backticks or with a lower-case segment is not a module
  reference in this README's idiom and is not read, which the docs census shares. A module
  named under *shipping now* must be among the modules compiled from `lib/`; a module named
  under any of the other three must not be -- a name that ships under "decided and not built"
  is a feature that shipped without the paragraph moving, and that is the drift this file
  exists to catch (the sentence a release slice writes and the next three slices leave
  behind). The *shipping now* paragraph must name at least one module, so the census cannot
  pass over an empty population; the other three name none today and the assertion over them
  is vacuous until one does, which is said rather than hidden.

  The shipping set is `BeamMCP.Boundary.lib_modules/0` -- the beams in the build's ebin whose
  compile-time source is under `lib/` -- and not the `.app`'s module list: under `mix test`
  the `.app` also lists everything compiled from `test/support` (fifteen modules that never
  ship), and a review lane showed three of them named under "shipping now" passing green
  against the `.app`. Shown red by plants in a scratch copy of the README: a module that
  exists (`BeamMCP.Connectome.Reach`) named under "decided and not built", a module that does
  not (`BeamMCP.Connectome.Federation`) and three `test/support` modules named under "shipping
  now" -- each named by paragraph in the failure. A module's *existence in the shipped set* is
  the whole claim; whether the paragraph describes it truly is the docs census's and a reader's.
  """
  use ExUnit.Case, async: true

  @readme Path.expand("../../README.md", __DIR__)
  @section "## What this package is, and is not"
  @leads ["Shipping now", "Decided and not built", "Scheduled", "Deliberately out"]

  # The four paragraphs, keyed by lead, from the file named in `path`.
  def split(path) do
    [_, section] = String.split(File.read!(path), @section, parts: 2)
    [section | _] = String.split(section, "\n## ", parts: 2)

    for lead <- @leads, into: %{} do
      [_, rest] = String.split(section, "**#{lead}.**", parts: 2)
      [paragraph | _] = String.split(rest, "\n\n", parts: 2)
      {lead, paragraph}
    end
  end

  def modules(paragraph) do
    ~r/`%?(?:Elixir\.)?(BeamMCP(?:\.[A-Z]\w*)+)(?:\{\}|\.[a-z_]\w*[?!]?\/\d+)?`/
    |> Regex.scan(paragraph, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.map(&Module.concat([&1]))
  end

  # The beams compiled from lib/ -- the set a consumer gets -- not the test build's `.app`,
  # which lists test/support beside them (see the moduledoc).
  defp shipped, do: MapSet.new(BeamMCP.Boundary.lib_modules())

  test "the section has its four paragraphs, in the README's order" do
    readme = File.read!(@readme)
    assert readme =~ @section

    positions = Enum.map(@leads, fn lead -> :binary.match(readme, "**#{lead}.**") |> elem(0) end)

    assert positions == Enum.sort(positions),
           "the four leads are out of order: #{inspect(@leads)}"
  end

  test "every module named under shipping now is compiled from lib/, and there is at least one" do
    named = modules(split(@readme)["Shipping now"])
    assert named != [], "\"Shipping now\" names no module; the census would pass over nothing"
    missing = Enum.reject(named, &MapSet.member?(shipped(), &1))

    assert missing == [],
           "named under \"Shipping now\" and not among the modules compiled from lib/: " <>
             inspect(missing)
  end

  test "no module named under decided and not built, scheduled, or deliberately out is compiled from lib/" do
    paragraphs = split(@readme)

    for lead <- @leads -- ["Shipping now"] do
      built = paragraphs[lead] |> modules() |> Enum.filter(&MapSet.member?(shipped(), &1))

      assert built == [],
             "named under \"#{lead}\" and compiled from lib/ -- the feature shipped and the " <>
               "paragraph did not move: #{inspect(built)}"
    end
  end
end
