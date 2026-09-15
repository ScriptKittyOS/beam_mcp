# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Boundary.NoAuthorityTest do
  # boundary: decides no authority
  # The package decides no authority: no line under lib/ names a receipt, an approval, a risk
  # tier, egress or a mask -- in the spellings code uses (`risk_tier`, `approved`, `{:tier, _}`,
  # `masked`) as well as the spellings prose uses. The verdict itself is held by value, not by
  # word: the sign census pins that the package writes only `:unknown` into an edge's sign slot,
  # and "verdict" as a word names that slot in the edge's own docs.
  use ExUnit.Case, async: true
  alias BeamMCP.Boundary

  @acts ~r/receipts?|approv|risk[ _-]?tiers?|\btiers?\b|egress|\bmask(ed|ing|s)?\b/i

  test "no line under lib/ names a receipt, an approval, a risk tier, egress or a mask, in any spelling" do
    hits = Boundary.hits(@acts)
    assert hits == [], "an act of authority under lib/:\n  " <> Boundary.format(hits)
  end
end
