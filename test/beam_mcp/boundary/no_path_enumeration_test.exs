# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Boundary.NoPathEnumerationTest do
  # boundary: enumerates no paths, matches no motifs
  # The one definition of `all_paths` under lib/ is the refusal, and nothing under lib/ defines
  # a motif or isomorphism function. The behaviour half -- `all_paths/4` returns the refusal on
  # any graph -- is the reach tests'; this census holds the source so that a second definition
  # or a matcher under another entry point cannot appear beside the refusal.
  use ExUnit.Case, async: true
  alias BeamMCP.Boundary

  @refusal ~s|def all_paths(%Graph{}, _from, _to, _opts \\\\ []), do: {:error, {:refused, :all_paths}}|
  @matcher ~r/\bdefp?\s+(motifs?|isomorph\w*|subgraph_match\w*|match_motif\w*|enumerate_paths|paths_between)\b/

  test "the only definition of all_paths under lib/ is the refusal, and no motif matcher is defined" do
    defs = Boundary.hits(~r/\bdefp?\s+all_paths\b/)

    assert length(defs) == 1, "all_paths defined other than once:\n  " <> Boundary.format(defs)
    [{_, _, line}] = defs

    assert String.trim(line) == @refusal, "all_paths is not the refusal: #{String.trim(line)}"
    hits = Boundary.hits(@matcher)

    assert hits == [],
           "a path enumerator or motif matcher under lib/:\n  " <> Boundary.format(hits)
  end
end
