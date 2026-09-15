# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Boundary.NoCatalogTest do
  # boundary: holds no tools, no domain, no concrete catalog
  # The catalog and the dispatch are the host's, injected: no module under lib/ implements
  # `BeamMCP.Catalog` -- by `@behaviour` or by exporting `capabilities/0`, which is all
  # `Catalog.validate/1` asks -- and nothing under lib/ builds a `%BeamMCP.ToolSpec{}` value: not
  # as a literal on one line or across several, not by `struct/2` or `struct!/2`. The struct is
  # defined there, matched there, and never constructed there. The one example under lib/ is
  # the prose of an ArgumentError, allowed by its shape (a doc line with no field named).
  use ExUnit.Case, async: true
  alias BeamMCP.Boundary

  @implements ~r/@behaviour\s+BeamMCP\.Catalog\b|@behaviour\s+Catalog\b|\bdefp?\s+capabilities\b/
  # A tool the package built would carry a literal name (an atom or a string); a pattern in a
  # clause head binds a variable there, and an example in prose has no fields. The literal is
  # read across lines (the README writes `name:` on the line after the opener), and `struct/2`
  # and `struct!/2` on the module are constructions whatever they carry.
  @literal ~r/%(BeamMCP\.)?ToolSpec\{[^}]*\bname:\s*(:\w+|")/s
  @by_function ~r/\bstruct!?\(\s*(BeamMCP\.)?ToolSpec\b/

  test "no module under lib/ implements BeamMCP.Catalog" do
    hits = Boundary.hits(@implements)
    assert hits == [], "a catalog under lib/:\n  " <> Boundary.format(hits)
    # And the behaviour is there to implement: the census is not reading an empty tree.
    assert Boundary.hits(~r/@callback capabilities\(\)/) != []
  end

  test "no line under lib/ constructs a tool" do
    hits = Boundary.hits(@by_function)
    assert hits == [], "a tool built under lib/:\n  " <> Boundary.format(hits)
    files = Boundary.file_hits(@literal)
    assert files == [], "a tool literal under lib/:\n  " <> Enum.join(files, "\n  ")
  end
end
