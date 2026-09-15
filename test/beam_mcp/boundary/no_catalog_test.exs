# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Boundary.NoCatalogTest do
  # boundary: holds no tools, no domain, no concrete catalog
  # The catalog and the dispatch are the host's, injected: no module under lib/ implements
  # `BeamMCP.Catalog`, and no line under lib/ builds a `%BeamMCP.ToolSpec{}` value -- the struct
  # is defined there, matched there, and never constructed there. The one example under lib/ is
  # the prose of an ArgumentError, allowed by its shape (a doc line, not a construction).
  use ExUnit.Case, async: true
  alias BeamMCP.Boundary

  @implements ~r/@behaviour\s+BeamMCP\.Catalog\b|@behaviour\s+Catalog\b/
  # A tool the package built would carry a literal name (an atom or a string); a pattern in a
  # clause head binds a variable there, and an example in prose has no fields.
  @constructs ~r/%(BeamMCP\.)?ToolSpec\{[^}]*\bname:\s*(:\w+|")/

  test "no module under lib/ implements BeamMCP.Catalog" do
    hits = Boundary.hits(@implements)
    assert hits == [], "a catalog under lib/:\n  " <> Boundary.format(hits)
    # And the behaviour is there to implement: the census is not reading an empty tree.
    assert Boundary.hits(~r/@callback capabilities\(\)/) != []
  end

  test "no line under lib/ constructs a tool" do
    hits = Boundary.hits(@constructs)
    assert hits == [], "a tool built under lib/:\n  " <> Boundary.format(hits)
  end
end
