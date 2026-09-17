# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Boundary.NoCatalogTest do
  # boundary: holds no tools, no domain, no concrete catalog
  # The catalog and the dispatch are the host's, injected: no module under lib/ implements
  # `BeamMCP.Catalog` -- by `@behaviour` or by exporting `capabilities/0`, which is all
  # `Catalog.validate/1` asks, by `def` or `defdelegate` -- and nothing under lib/ builds a
  # `%BeamMCP.ToolSpec{}` value, in any spelling: the census reads the COMPILED forms, where a
  # struct pattern is the one place the module's atom may appear. The struct is defined there,
  # matched there, and never constructed there. The catalog is called through three callees,
  # `capabilities/0` at five sites, `read_resource/1` at one and `get_prompt/2` at one -- and,
  # from the artefact, every call through a module known only at runtime is one of those seven.
  use ExUnit.Case, async: true
  alias BeamMCP.Boundary

  @implements ~r/@behaviour\s+BeamMCP\.Catalog\b|@behaviour\s+Catalog\b|\bdef(p|delegate|macro)?\s+capabilities\b/

  test "no module under lib/ implements BeamMCP.Catalog" do
    hits = Boundary.hits(@implements)
    assert hits == [], "a catalog under lib/:\n  " <> Boundary.format(hits)
    # And the behaviour is there to implement: the census is not reading an empty tree.
    assert Boundary.hits(~r/@callback capabilities\(\)/) != []
    # From the artefact: no module compiled from lib/ exports capabilities/0.
    exporters = for m <- Boundary.lib_modules(), function_exported?(m, :capabilities, 0), do: m
    assert exporters == [], "modules under lib/ exporting capabilities/0: #{inspect(exporters)}"
  end

  test "no line under lib/ constructs a tool" do
    # In the compiled forms the alias is resolved, a pattern's fields are `map_field_exact` and
    # a literal's are `map_field_assoc`, and `struct/2`, `Map.put/3`, a pipe, a variable bound
    # to the module and `%{m | __struct__: _}` all leave the atom somewhere that is not a
    # pattern. Compiler-generated sites (module_info, the struct's own __struct__/0,1) are not
    # read. So: at every real site, the atom is a pattern's `__struct__`.
    #
    # The struct's own `__struct__/1` -- `defstruct`'s generated builder inside BeamMCP.ToolSpec
    # itself -- is the struct's DEFINITION, not a line constructing a tool. Elixir 1.18+ marks
    # that site `generated`; Elixir 1.17 leaves it at the `defstruct` line (measured on the CI
    # floor leg: `{BeamMCP.ToolSpec, 12, {:construction, :__struct__}}`), so it is named here by
    # what it is rather than by the mark a given compiler gives it.
    sites = Boundary.atom_sites(BeamMCP.ToolSpec)

    real =
      for {m, loc, ctx} <- sites,
          not Boundary.generated?(loc),
          {m, ctx} != {BeamMCP.ToolSpec, {:construction, :__struct__}},
          do: {m, loc, ctx}

    not_patterns = for {_, _, ctx} = site <- real, ctx != {:pattern, :__struct__}, do: site

    assert not_patterns == [],
           "BeamMCP.ToolSpec used other than as a pattern under lib/:\n  " <>
             Enum.map_join(not_patterns, "\n  ", &inspect/1)

    # The reader sees the struct where it is matched, or it is reading nothing.
    assert length(real) >= 4

    # The generated sites are not skipped: they are pinned. The compiler writes the struct's
    # own __struct__/0,1 (two constructions, six values) and Catalog's callback info (three
    # values), and nothing else -- an `unquote` of a hand-built AST carrying `generated: true`
    # (a lane's plant) is a fourth generated construction, and fails here.
    generated = for {m, loc, ctx} <- sites, Boundary.generated?(loc), do: {m, ctx}

    assert Enum.frequencies(generated) == %{
             {BeamMCP.Catalog, :value} => 3,
             {BeamMCP.ToolSpec, :value} => 6,
             {BeamMCP.ToolSpec, {:construction, :__struct__}} => 2
           },
           "generated sites of BeamMCP.ToolSpec: #{inspect(Enum.frequencies(generated))}"
  end

  # The names the package reaches by dot syntax, from the compiled forms. A field access and a
  # call without parentheses through a runtime module (`m.capabilities`, a deprecated form)
  # compile to the same branch, so the artefact cannot tell them apart -- but every name is
  # listed, and the list is the package's own fields. `capabilities` is not among them.
  @dotted ~w(__struct__ allowed_origins allowlisted ancestor authorize authorize_body bucket
    catalog classes collector command_class companion connection_timeout coverage description dfnum dispatch
    dispatch_opts edges entries external from id idom input_schema kind kinds label labels level
    macro max_duration_ms method mode module_ids modules name no_beam no_debug_info nodes parent
    pids provenance read_timeout schema_version semi server server_name server_opts shutdown? sign sources
    supported_versions to tools tools_cache_scope tools_ttl_ms ungrouped ungrouped_calls
    unreadable unresolved weight window
    annotations icons mime_type page_size resources resources_cache_scope resources_ttl_ms
    size title uri uri_template arguments prompts prompts_cache_scope prompts_ttl_ms required
    cache definition items key key_fun)a

  test "the catalog is called through three callees: capabilities/0 at five sites, read_resource/1 at one, get_prompt/2 at one" do
    # From the artefact: every call whose module is only known at runtime and whose function
    # is named (`:"$M_EXPR"` with a real function) is one of the catalog's three callbacks --
    # `capabilities/0` (the tools reader, the one reader behind both resource readers, the
    # prompts reader, the validator, the connectome builder), `read_resource/1` (the one read
    # site, reached only after `readable?/2` has said yes from `capabilities/0`) and
    # `get_prompt/2` (the one render site, reached only after `fetch_prompt/2` has found the
    # name through `capabilities/0` and the tools validator has passed the arguments). A
    # `:"$F_EXPR"` is a call through a function value -- the host's dispatch and hooks, and
    # the package's own closures -- and is not a module call.
    {_edges, unresolved} = Boundary.xref()
    named = for {from, {:"$M_EXPR", f, a}} <- unresolved, f != :"$F_EXPR", do: {from, f, a}

    assert Enum.sort(named) == [
             {{BeamMCP.Catalog, :entries, 1}, :capabilities, 0},
             {{BeamMCP.Catalog, :prompts, 1}, :capabilities, 0},
             {{BeamMCP.Catalog, :tools, 1}, :capabilities, 0},
             {{BeamMCP.Catalog, :validate_shape, 1}, :capabilities, 0},
             {{BeamMCP.Connectome.Declared, :read_catalog, 2}, :capabilities, 0},
             {{BeamMCP.Server, :get_prompt, 4}, :get_prompt, 2},
             {{BeamMCP.Server, :read_resource, 3}, :read_resource, 1}
           ],
           "calls through a variable module:\n  " <> Enum.map_join(named, "\n  ", &inspect/1)

    sites = Boundary.hits(~r/\.capabilities\(\)/)

    assert length(sites) == 5,
           "capabilities/0 call sites in the text:\n  " <> Boundary.format(sites)

    reads = Boundary.hits(~r/\.read_resource\(/)

    assert length(reads) == 1,
           "read_resource/1 call sites in the text:\n  " <> Boundary.format(reads)

    renders = Boundary.hits(~r/\.get_prompt\(/)

    assert length(renders) == 1,
           "get_prompt/2 call sites in the text:\n  " <> Boundary.format(renders)
  end

  test "every name the package reaches by dot syntax is on its pinned list" do
    names = Boundary.dotted_names()

    assert Enum.sort(names) == Enum.sort(@dotted),
           "dotted names not on the list: #{inspect(Enum.sort(names -- @dotted))}; listed, unused: #{inspect(Enum.sort(@dotted -- names))}"
  end
end
