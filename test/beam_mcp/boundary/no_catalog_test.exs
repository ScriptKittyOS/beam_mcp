# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Boundary.NoCatalogTest do
  # boundary: holds no tools, no domain, no concrete catalog
  # The catalog and the dispatch are the host's, injected: no module under lib/ implements
  # `BeamMCP.Catalog` -- by `@behaviour` or by exporting `capabilities/0`, which is all
  # `Catalog.validate/1` asks -- and nothing under lib/ builds a `%BeamMCP.ToolSpec{}` value: not
  # as a literal in any field order or across any lines, not as a `%{__struct__: ...}` map, not
  # through `struct/2`, `struct!/2` or `__struct__/1`. The literal is read from the AST, where a
  # clause-head pattern and a `match?/2` are matches and everything else is a construction. The
  # struct is defined there, matched there, and never constructed there. The catalog is called
  # through one callee, `capabilities/0`, at a counted number of sites, so that a fourth has to
  # be named on the page.
  use ExUnit.Case, async: true
  alias BeamMCP.Boundary

  @implements ~r/@behaviour\s+BeamMCP\.Catalog\b|@behaviour\s+Catalog\b|\bdefp?\s+capabilities\b/
  @tool_spec [[:ToolSpec], [:BeamMCP, :ToolSpec]]
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
    built = Boundary.struct_constructions(@tool_spec)

    assert built == [],
           "a ToolSpec constructed under lib/:\n  " <>
             Enum.map_join(built, "\n  ", fn {p, l} -> "#{p}:#{l}" end)

    # The reader sees the struct where it is matched, or it is reading nothing.
    assert Boundary.hits(~r/%(BeamMCP\.)?ToolSpec\{/) != []
  end

  test "the catalog is called through one callee, capabilities/0, at three sites" do
    sites = Boundary.hits(~r/\.capabilities\(\)/)
    assert length(sites) == 3, "capabilities/0 call sites:\n  " <> Boundary.format(sites)
    assert Boundary.hits(~r/\bcatalog\.\w+\(|\bmodule\.\w+\(/) -- sites == []
  end
end
