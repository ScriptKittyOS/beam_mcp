# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Connectome.DeclaredTest do
  use ExUnit.Case, async: true

  alias BeamMCP.Connectome.{Declared, Edge, Graph, Node}
  alias BeamMCP.Fixture.Declared, as: Fx

  @modules [Fx.Alpha, Fx.Beta, Fx.Gamma, Fx.MacroOnly, Fx.Dyn, Fx.Catalog]
  @server "fx"

  defp build(extra \\ []) do
    Declared.build(
      Keyword.merge(
        [
          server: @server,
          catalog: Fx.Catalog,
          modules: @modules,
          tool_modules: %{echo: Fx.Alpha}
        ],
        extra
      )
    )
  end

  defp ids(nodes), do: nodes |> Enum.map(& &1.id) |> Enum.sort()
  defp keys(edges), do: edges |> Enum.map(&Edge.key/1) |> Enum.sort()

  describe "the fixture app, at the :module level" do
    test "yields exactly the expected node set and edge set -- the full sets, not a subset" do
      assert {:ok, %Declared.Result{graph: %Graph{} = g}} = build()

      expected_nodes =
        [
          Node.id({:server, @server}),
          Node.id({:tool, @server, :echo}),
          Node.id({:tool, @server, :write}),
          Node.id({:resource, @server, "r://a"}),
          Node.id({:prompt, @server, "greet"})
        ] ++ Enum.map(@modules, &Node.id({:module, @server, &1}))

      assert ids(g.nodes) == Enum.sort(expected_nodes)

      s = Node.id({:server, @server})
      echo = Node.id({:tool, @server, :echo})
      write = Node.id({:tool, @server, :write})
      alpha = Node.id({:module, @server, Fx.Alpha})
      beta = Node.id({:module, @server, Fx.Beta})

      assert keys(g.edges) ==
               Enum.sort([
                 {s, echo, :invoke, :declared},
                 {s, write, :invoke, :declared},
                 {echo, alpha, :invoke, :declared},
                 {alpha, beta, :invoke, :declared}
               ])

      assert Enum.all?(
               g.edges,
               &(&1.provenance == :declared and &1.sign == :unknown and &1.weight == nil)
             )
    end

    test "a tool node carries command_class and mode as labels; module nodes are at :module" do
      {:ok, %{graph: g}} = build()
      echo = Enum.find(g.nodes, &(&1.id == Node.id({:tool, @server, :echo})))
      assert echo.kind == :tool and echo.level == :server
      assert echo.labels == %{command_class: :observe, mode: :read_only}
      alpha = Enum.find(g.nodes, &(&1.id == Node.id({:module, @server, Fx.Alpha})))
      assert alpha.kind == :module and alpha.level == :module
    end

    test "a compile-time-only dependency is not an edge, and an uncalled module is still a node" do
      {:ok, %{graph: g}} = build()
      macro = Node.id({:module, @server, Fx.MacroOnly})
      gamma = Node.id({:module, @server, Fx.Gamma})
      refute Enum.any?(g.edges, &(&1.to == macro or &1.from == macro))
      assert Enum.any?(g.nodes, &(&1.id == gamma))
      refute Enum.any?(g.edges, &(&1.to == gamma or &1.from == gamma))
    end

    test "two consecutive builds are equal, and so is a build from shuffled inputs" do
      {:ok, a} = build()
      {:ok, b} = build()
      assert a == b

      for _ <- 1..10 do
        {:ok, c} = build(modules: Enum.shuffle(@modules))
        assert c == a
      end
    end
  end

  describe "the completeness bound" do
    test "every dynamic-dispatch site is enumerated by its caller, never summarised to a count" do
      {:ok, %{bound: %Declared.Bound{} = bound}} = build()

      assert Enum.map(bound.unresolved_calls, &elem(&1, 0)) ==
               Enum.sort([{Fx.Dyn, :apply_to, 2}, {Fx.Dyn, :call, 2}, {Fx.Dyn, :fun, 2}])

      # The three shapes, as xref reports them: a dynamic module call and a fun call are
      # $M_EXPR calls; apply/3 with a variable argument list is a $M_EXPR call of arity -1,
      # which is xref's spelling of "arity unknown". Measured, not assumed: a first draft
      # looked for a resolved call to :erlang.apply/3 and there is none.
      assert {{Fx.Dyn, :apply_to, 2}, {:"$M_EXPR", :run, -1}} in bound.unresolved_calls
      assert {{Fx.Dyn, :call, 2}, {:"$M_EXPR", :run, 1}} in bound.unresolved_calls
      assert {{Fx.Dyn, :fun, 2}, {:"$M_EXPR", :"$F_EXPR", 1}} in bound.unresolved_calls

      assert bound.allowlisted_calls == []
    end

    test "an allowlisted site moves from unresolved to allowlisted, by name" do
      {:ok, %{bound: bound}} = build(dynamic_allowlist: [{Fx.Dyn, :fun, 2}])

      assert Enum.map(bound.unresolved_calls, &elem(&1, 0)) == [
               {Fx.Dyn, :apply_to, 2},
               {Fx.Dyn, :call, 2}
             ]

      assert Enum.map(bound.allowlisted_calls, &elem(&1, 0)) == [{Fx.Dyn, :fun, 2}]
    end

    test "a catalog entry no reader can name is enumerated, and has no node" do
      {:ok, %{graph: g, bound: bound}} = build()
      assert bound.unreadable_catalog_entries == [{:resources, :opaque}]
      assert length(Enum.filter(g.nodes, &(&1.kind == :resource))) == 1
    end

    test "callees outside the scope are neither nodes nor edges, and are enumerated by module" do
      {:ok, %{graph: g, bound: bound}} =
        build(modules: [Fx.Alpha, Fx.Beta, Fx.Gamma, Fx.Dyn, Fx.Catalog, Fx.Outward])

      assert :calendar in bound.external_callees
      refute Enum.any?(g.nodes, &(&1.id == Node.id({:module, @server, :calendar})))
      assert bound.external_callees == Enum.sort(bound.external_callees)
      # A dynamic target is not a callee outside the scope; it is an unresolved site.
      refute :"$M_EXPR" in bound.external_callees
    end

    test "a call a macro body makes at expansion time is an expansion call, not a runtime edge or callee" do
      # xref attributes such calls to the `MACRO-name` function. They run in the compiler, not
      # in the system, so they are neither :invoke edges nor callees outside the scope; they
      # are enumerated by their macro, because a reader of the bound must be able to see them.
      {:ok, %{graph: g, bound: bound}} = build()
      refute :elixir_quote in bound.external_callees

      assert bound.macro_expansion_calls == [
               {{Fx.MacroOnly, :"MACRO-twice", 2}, {Fx.MacroHelper, :note, 1}},
               {{Fx.MacroOnly, :"MACRO-twice", 2}, {:elixir_quote, :shallow_validate_ast, 1}}
             ]

      # An in-scope module called only from a macro body: an expansion call, and no edge.
      helper = Node.id({:module, @server, Fx.MacroHelper})
      {:ok, %{graph: g2, bound: bound2}} = build(modules: @modules ++ [Fx.MacroHelper])
      refute Enum.any?(g2.edges, &(&1.to == helper))

      assert Enum.any?(
               bound2.macro_expansion_calls,
               &match?({{Fx.MacroOnly, :"MACRO-twice", 2}, {Fx.MacroHelper, :note, 1}}, &1)
             )

      _ = g
    end

    test "a tool with no implementing module is enumerated" do
      {:ok, %{bound: bound}} = build()
      assert bound.tools_without_module == [:write]
    end

    test "a tool whose named module is outside the scope is enumerated too, never a dangling edge" do
      {:ok, %{graph: g, bound: bound}} = build(tool_modules: %{echo: Not.In.Scope})
      assert bound.tools_without_module == [:echo, :write]
      refute Enum.any?(g.edges, &(&1.from == Node.id({:tool, @server, :echo})))
    end

    test "a module with no beam on the code path is enumerated, not invented" do
      {:ok, %{graph: g, bound: bound}} = build(modules: [Fx.Beta, Not.A.Module])
      assert bound.modules_without_beam == [Not.A.Module]
      refute Enum.any?(g.nodes, &(&1.id == Node.id({:module, @server, Not.A.Module})))
    end

    test "the sources used are named" do
      {:ok, %{bound: bound}} = build()
      assert bound.sources_used == [:catalog, :xref]
    end
  end

  describe "options" do
    test "server is required and must be a string" do
      assert {:error, {:missing, :server}} = Declared.build(modules: @modules)
      assert {:error, {:invalid, :server, :fx}} = Declared.build(server: :fx, modules: @modules)
    end

    test "modules or apps must be given; an unknown key is refused" do
      assert {:error, {:missing, :modules}} = Declared.build(server: @server)
      assert {:error, {:unknown_key, :signs}} = build(signs: %{})
    end

    test "apps: derives the module population from each .app file's modules key" do
      {:ok, %{graph: g}} = Declared.build(server: @server, apps: [:beam_mcp], level: :module)
      mods = Application.spec(:beam_mcp, :modules)

      assert Enum.sort(Enum.map(g.nodes, & &1.id)) ==
               Enum.sort([
                 Node.id({:server, @server}) | Enum.map(mods, &Node.id({:module, @server, &1}))
               ])
    end

    test "boundary reflection is refused by name until it is measured" do
      assert {:error, {:unsupported, :boundaries, :reflect}} =
               build(level: :boundary, boundaries: :reflect)
    end
  end

  describe "the :mfa level" do
    test "one node per function that calls or is called within scope, and edges between them" do
      {:ok, %{graph: g}} = build(level: :mfa, modules: [Fx.Alpha, Fx.Beta])
      alpha_run = Node.id({:module, @server, {Fx.Alpha, :run, 1}})
      beta_run = Node.id({:module, @server, {Fx.Beta, :run, 1}})
      assert Enum.any?(g.nodes, &(&1.id == alpha_run and &1.level == :mfa))
      assert {alpha_run, beta_run, :invoke, :declared} in keys(g.edges)
    end
  end

  describe "the :boundary level" do
    test "a host map collapses modules into their groups, drops self-loops, keeps the ungrouped enumerated" do
      map = %{
        Fx.Alpha => {:application, :grp},
        Fx.Beta => {:application, :grp},
        Fx.Gamma => {:boundary_module, Fx.Gamma}
      }

      {:ok, %{graph: g, bound: bound}} =
        build(
          level: :boundary,
          boundaries: map,
          modules: [Fx.Alpha, Fx.Beta, Fx.Gamma, Fx.Dyn],
          catalog: nil,
          tool_modules: %{}
        )

      grp = Node.id({:boundary, @server, :application, :grp})
      gam = Node.id({:boundary, @server, :boundary_module, Fx.Gamma})
      assert ids(Enum.filter(g.nodes, &(&1.kind == :module))) == Enum.sort([grp, gam])
      assert Enum.all?(Enum.filter(g.nodes, &(&1.kind == :module)), &(&1.level == :boundary))
      # Alpha -> Beta is inside :grp: a self-loop after collapse, and dropped.
      assert keys(g.edges) == []
      assert bound.ungrouped_modules == [Fx.Dyn]
    end

    test "a call across two groups is one edge between the groups, at the :boundary level" do
      map = %{Fx.Alpha => {:application, :one}, Fx.Beta => {:boundary_module, Fx.Beta}}

      {:ok, %{graph: g}} =
        build(
          level: :boundary,
          boundaries: map,
          modules: [Fx.Alpha, Fx.Beta],
          catalog: nil,
          tool_modules: %{}
        )

      one = Node.id({:boundary, @server, :application, :one})
      two = Node.id({:boundary, @server, :boundary_module, Fx.Beta})
      assert keys(g.edges) == [{one, two, :invoke, :declared}]
      assert Enum.all?(g.edges, &(&1.weight == nil and &1.sign == :unknown))
    end

    test "a call into or out of an ungrouped module is enumerated, never an edge and never dropped" do
      # Alpha calls Beta. Beta is grouped; Alpha is not. The call cannot be an edge (one end has
      # no node at this level) and it must not vanish: the compiled code showed it.
      map = %{Fx.Beta => {:application, :grp}}

      {:ok, %{graph: g, bound: bound}} =
        build(
          level: :boundary,
          boundaries: map,
          modules: [Fx.Alpha, Fx.Beta],
          catalog: nil,
          tool_modules: %{}
        )

      assert bound.ungrouped_modules == [Fx.Alpha]
      assert bound.ungrouped_calls == [{{Fx.Alpha, :run, 1}, {Fx.Beta, :run, 1}}]
      assert keys(g.edges) == []
    end

    test "without a host map, modules group by their OTP application; those with none are enumerated" do
      {:ok, %{graph: g, bound: bound}} =
        build(level: :boundary, modules: [Fx.Alpha, Fx.Beta], catalog: nil, tool_modules: %{})

      app = Node.id({:boundary, @server, :application, :beam_mcp})
      assert Enum.any?(g.nodes, &(&1.id == app))
      assert bound.ungrouped_modules == []
    end
  end

  describe "beams the code path holds that no application claims, or that carry no debug information" do
    # Written to a scratch directory and put on the code path, so they are found by name the
    # way any module's beam is -- and belong to no OTP application, because nothing loaded
    # them from one.
    setup do
      dir =
        Path.join(System.tmp_dir!(), "beam_mcp_declared_#{System.unique_integer([:positive])}")

      File.mkdir_p!(dir)

      # `mix test` runs with the compiler option `debug_info: false`, measured: a module
      # compiled at test time carries `:none`, and xref refuses it as if it were stripped. The
      # option is turned on for these two compiles, so the orphan is a readable beam and the
      # stripped one is stripped by `:beam_lib.strip/1` and by nothing else.
      was = Code.get_compiler_option(:debug_info)
      Code.put_compiler_option(:debug_info, true)

      [{Orphan, plain}] = Code.compile_string("defmodule Orphan do\n  def go, do: :ok\nend")
      File.write!(Path.join(dir, "Elixir.Orphan.beam"), plain)

      [{Stripped, full}] = Code.compile_string("defmodule Stripped do\n  def go, do: :ok\nend")
      {:ok, {Stripped, stripped}} = :beam_lib.strip(full)
      File.write!(Path.join(dir, "Elixir.Stripped.beam"), stripped)

      Code.put_compiler_option(:debug_info, was)

      {:ok, {Orphan, [debug_info: {:debug_info_v1, :elixir_erl, {:elixir_v1, _, _}}]}} =
        :beam_lib.chunks(plain, [:debug_info])

      true = Code.append_path(dir)

      on_exit(fn ->
        Code.delete_path(dir)
        File.rm_rf!(dir)
      end)

      :ok
    end

    test "a module with no application is enumerated at the :boundary level, never guessed into a group" do
      {:ok, %{graph: g, bound: bound}} =
        Declared.build(server: @server, modules: [Fx.Beta, Orphan], level: :boundary)

      assert bound.ungrouped_modules == [Orphan]
      assert bound.sources_used == [:application, :xref]

      assert ids(g.nodes) ==
               Enum.sort([
                 Node.id({:server, @server}),
                 Node.id({:boundary, @server, :application, :beam_mcp})
               ])
    end

    test "a beam without debug information is enumerated, and is not a node" do
      {:ok, %{graph: g, bound: bound}} =
        Declared.build(server: @server, modules: [Fx.Beta, Stripped])

      assert bound.modules_without_debug_info == [Stripped]
      refute Enum.any?(g.nodes, &(&1.id == Node.id({:module, @server, Stripped})))
    end
  end

  describe "refusals by name" do
    defmodule DoubledCatalog do
      @behaviour BeamMCP.Catalog
      @impl true
      def capabilities do
        t = %BeamMCP.ToolSpec{
          name: :echo,
          command_class: :observe,
          mode: :read_only,
          description: "x"
        }

        %{tools: [t, t], resources: [], prompts: []}
      end
    end

    test "a catalog naming one tool twice is a graph refusal, reported as such" do
      assert {:error, {:graph, {:duplicate_node, id}}} =
               Declared.build(server: @server, modules: [Fx.Beta], catalog: DoubledCatalog)

      assert id == Node.id({:tool, @server, :echo})
    end

    test "an application no .app file describes is refused by name, not built as empty" do
      assert {:error, {:unknown_app, :no_such_app_zz}} =
               Declared.build(server: @server, apps: [:no_such_app_zz])
    end

    test "a module or app list holding a non-atom is refused by name" do
      assert {:error, {:invalid, :modules, ["NotAnAtom"]}} =
               Declared.build(server: @server, modules: ["NotAnAtom"])

      assert {:error, {:invalid, :apps, ["beam_mcp"]}} =
               Declared.build(server: @server, apps: ["beam_mcp"])
    end

    defmodule PlainMapTool do
      @behaviour BeamMCP.Catalog
      @impl true
      def capabilities, do: %{tools: [%{name: :plain}], resources: [], prompts: []}
    end

    test "a catalog the package's own contract check refuses is refused here by the same reason, and never read" do
      assert {:error, {:invalid, :catalog, reason}} = build(catalog: PlainMapTool)
      assert reason =~ "ToolSpec"
      assert {:error, {:invalid, :catalog, reason2}} = build(catalog: :not_a_catalog)
      assert reason2 =~ "capabilities/0"
    end

    test "each malformed option is refused by its name" do
      assert {:error, {:invalid, :catalog, "nope"}} = build(catalog: "nope")
      assert {:error, {:invalid, :boundaries, [:x]}} = build(boundaries: [:x])

      assert {:error, {:invalid, :modules, :not_a_list}} =
               Declared.build(server: @server, modules: :not_a_list)

      assert {:error, {:invalid, :apps, :not_a_list}} =
               Declared.build(server: @server, apps: :not_a_list)

      assert {:error, {:invalid, :modules, :both_modules_and_apps}} = build(apps: [:beam_mcp])
      assert {:error, {:invalid, :level, :neuropil}} = build(level: :neuropil)
      assert {:error, {:invalid, :opts, nil}} = Declared.build(nil)
    end
  end

  describe "the tree as its own fixture" do
    test "the bound's unresolved calls are exactly what xref reports for the package" do
      mods = Application.spec(:beam_mcp, :modules)
      {:ok, %{bound: bound}} = Declared.build(server: "beam_mcp", modules: mods)

      {:ok, ref} = :xref.start([])
      :xref.set_default(ref, warnings: false, verbose: false)

      for m <- mods,
          {_, _, file} <- [:code.get_object_code(m)],
          do: {:ok, _} = :xref.add_module(ref, file)

      {:ok, uc} = :xref.q(ref, ~c"UC")
      :xref.stop(ref)

      assert bound.unresolved_calls == Enum.sort(uc)
      assert bound.external_callees == Enum.sort(Enum.uniq(bound.external_callees))
      assert length(bound.external_callees) > 1

      assert {{BeamMCP.Server, :validate_and_dispatch, 3}, {:"$M_EXPR", :"$F_EXPR", 3}} in bound.unresolved_calls
    end
  end
end
