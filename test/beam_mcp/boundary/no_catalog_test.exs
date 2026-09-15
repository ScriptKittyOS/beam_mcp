# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Boundary.NoCatalogTest do
  # boundary: holds no tools, no domain, no concrete catalog
  # The catalog and the dispatch are the host's, injected: no module under lib/ implements
  # `BeamMCP.Catalog` -- by `@behaviour` or by exporting `capabilities/0`, which is all
  # `Catalog.validate/1` asks, by `def` or `defdelegate` -- and nothing under lib/ builds a
  # `%BeamMCP.ToolSpec{}` value: not as a literal in any field order or across any lines, not as
  # a `%{__struct__: ...}` map or a `Map.put(_, :__struct__, _)`, not through `struct/2`,
  # `struct!/2` or `__struct__/1`, and not as `%__MODULE__{}` inside the struct's own module.
  # Every shape is read from the AST, where a clause-head pattern and a `match?/2` are matches
  # and everything else is a construction. The struct is defined there, matched there, and never
  # constructed there. The catalog is called through one callee, `capabilities/0`, at a counted
  # number of sites -- and every call through a variable module under lib/ is one of them.
  use ExUnit.Case, async: true
  alias BeamMCP.Boundary

  @implements ~r/@behaviour\s+BeamMCP\.Catalog\b|@behaviour\s+Catalog\b|\bdef(p|delegate|macro)?\s+capabilities\b/
  @tool_spec [[:ToolSpec], [:BeamMCP, :ToolSpec]]
  # A call on a lowercase variable as a module: `catalog.capabilities()`, never `:ets.new(` or
  # `Enum.map(` (a colon or a capital before the dot), never `f.(x)` (an anonymous function).
  @variable_module_call ~r/(?<![:\w.@])[a-z_]\w*\.[a-z_]\w*\(/

  test "no module under lib/ implements BeamMCP.Catalog" do
    hits = Boundary.hits(@implements)
    assert hits == [], "a catalog under lib/:\n  " <> Boundary.format(hits)
    # And the behaviour is there to implement: the census is not reading an empty tree.
    assert Boundary.hits(~r/@callback capabilities\(\)/) != []
  end

  test "no line under lib/ constructs a tool" do
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
    others = Boundary.hits(@variable_module_call) -- sites

    assert others == [],
           "a call through a variable module other than the catalog:\n  " <>
             Boundary.format(others)
  end
end
