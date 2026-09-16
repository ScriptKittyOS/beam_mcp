# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Connectome.SurfaceTest do
  @moduledoc """
  The connectome on the wire: three read-only resources and one `:observe` tool a host may put
  in its catalog, each answering the canonical bytes of a graph -- byte-identical to the file
  export -- and nothing else. No capability is claimed for it (there is none to claim); the
  wire the package already emits does not move (`wire_recording_test.exs` holds that).
  Written red before `BeamMCP.Connectome.Surface` existed.
  """
  use ExUnit.Case, async: false

  alias BeamMCP.{Catalog, ResourceSpec, Server, ToolSpec}
  alias BeamMCP.Connectome.{Canonical, Declared, Diff, Observed, Surface}
  alias BeamMCP.Fixture.ConnectomeTool
  alias BeamMCP.Fixture.Declared, as: Fx

  # The one tool, as the moduledoc tells a host to write it: the package holds none (the
  # will-not-implement page's entry 11), so the spec lives on the host's side, in a fixture.

  @modules [Fx.Alpha, Fx.Beta, Fx.Gamma, Fx.MacroOnly, Fx.Dyn, Fx.Catalog]
  @declared [
    server: "fx",
    catalog: Fx.Catalog,
    modules: @modules,
    tool_modules: %{echo: Fx.Alpha}
  ]
  @window %{"started_at" => "2026-09-14T00:00:00Z", "ended_at" => "2026-09-14T01:00:00Z"}
  @export Path.expand("../../../livebooks/exports/fx.declared.json", __DIR__)

  @modern %{
    "io.modelcontextprotocol/protocolVersion" => "2026-07-28",
    "io.modelcontextprotocol/clientCapabilities" => %{}
  }

  # A collector with a few observed calls, stopped after the test.
  defp collector(context) do
    name = Module.concat(__MODULE__, :"c#{System.unique_integer([:positive])}")
    start_supervised!({Observed, name: name}, id: name)

    for t <- [:echo, :echo, :write],
        do: Observed.observe(name, {:server, "fx"}, {:tool, "fx", t}, :invoke, 3)

    Map.put(context, :collector, name)
  end

  setup :collector

  describe "the resources" do
    test "are three ResourceSpecs, one per graph, JSON, and a catalog carrying them validates" do
      specs = Surface.resources()

      assert Enum.map(specs, & &1.uri) ==
               ~w(connectome://declared connectome://diff connectome://observed)

      assert Enum.all?(specs, &match?(%ResourceSpec{mime_type: "application/json"}, &1))
      assert Enum.all?(specs, &(is_binary(&1.description) and &1.description != ""))
    end

    test "connectome://declared answers the canonical bytes, byte-identical to the tracked file export" do
      assert {:ok, [%{uri: "connectome://declared", text: bytes, mime_type: "application/json"}]} =
               Surface.read("connectome://declared", declared: @declared)

      assert bytes == File.read!(@export)
      {:ok, %Declared.Result{graph: g}} = Declared.build(@declared)
      assert bytes == Canonical.to_json!(g)
      assert :crypto.hash(:sha256, bytes) == Canonical.hash!(g)
    end

    test "connectome://observed answers the collector's snapshot as the file export writes it", %{
      collector: c
    } do
      assert {:ok, [%{uri: "connectome://observed", text: bytes}]} =
               Surface.read("connectome://observed", observed: c)

      {:ok, g} = Observed.snapshot(c)
      assert bytes == Canonical.to_json!(g)
      # Every sign the package writes is :unset (the standalone value): nothing else in the bytes.
      refute bytes =~ ~s("sign":"allow")
      assert bytes =~ ~s("sign":"unset")
    end

    test "connectome://diff answers the diff record over the consumer's window, as Diff.encode!/1 writes it",
         %{collector: c} do
      assert {:ok, [%{uri: "connectome://diff", text: bytes}]} =
               Surface.read("connectome://diff",
                 declared: @declared,
                 observed: c,
                 window: @window
               )

      {:ok, %Declared.Result{graph: d}} = Declared.build(@declared)
      {:ok, o} = Observed.snapshot(c)
      {:ok, diff} = Diff.run(d, o, window: @window)
      assert bytes == Diff.encode!(diff)
      assert Jason.decode!(bytes)["window"] == @window
    end

    test "refusals are by name: a missing input, a collector not started, an unknown uri", %{
      collector: c
    } do
      assert {:error, {:missing, :declared}} = Surface.read("connectome://declared", [])
      assert {:error, {:missing, :observed}} = Surface.read("connectome://observed", [])

      assert {:error, {:missing, :window}} =
               Surface.read("connectome://diff", declared: @declared, observed: c)

      assert {:error, :not_started} =
               Surface.read("connectome://observed", observed: :no_such_collector)

      assert {:error, {:unknown_uri, "connectome://reach"}} =
               Surface.read("connectome://reach", declared: @declared)

      # A build refusal is the builder's, verbatim: the same term Declared.build/1 answers.
      {:error, reason} = Declared.build(server: "fx")
      assert {:error, ^reason} = Surface.read("connectome://declared", declared: [server: "fx"])
    end
  end

  describe "the tool" do
    test "the spec the moduledoc gives a host is one :observe read-only ToolSpec admitting exactly the three graph names, and lib/ holds none" do
      assert %ToolSpec{name: :connectome, command_class: :observe, mode: :read_only} =
               tool = ConnectomeTool.spec()

      assert tool.input_schema["properties"]["graph"]["enum"] == ~w(declared observed diff)
      assert tool.input_schema["required"] == ["graph"]
      assert tool.input_schema["additionalProperties"] == false
      refute function_exported?(Surface, :tool, 0)
      # The moduledoc's copy is this spec, field for field.
      {:docs_v1, _, _, _, %{"en" => doc}, _, _} = Code.fetch_docs(Surface)

      for line <- [
            "name: :connectome",
            "command_class: :observe",
            "mode: :read_only",
            ~S|"required" => ["graph"]|,
            ~S|"additionalProperties" => false|
          ],
          do: assert(doc =~ line)
    end

    test "call/2 answers the graph's name, its bytes verbatim and their sha256", %{collector: c} do
      assert {:ok, %{graph: "declared", bytes: bytes, sha256: hex}} =
               Surface.call(%{graph: "declared"}, declared: @declared)

      assert bytes == File.read!(@export)
      assert hex == Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

      assert {:ok, %{graph: "observed", bytes: o}} =
               Surface.call(%{graph: "observed"}, observed: c)

      {:ok, g} = Observed.snapshot(c)
      assert o == Canonical.to_json!(g)

      assert {:error, {:missing, :window}} =
               Surface.call(%{graph: "diff"}, declared: @declared, observed: c)

      assert {:error, {:unknown_graph, "reach"}} =
               Surface.call(%{graph: "reach"}, declared: @declared)
    end

    test "call/2 never mutates: the collector's rows and the package's persistent terms are equal before and after",
         %{collector: c} do
      before = {Observed.rows(c), package_terms()}
      {:ok, _} = Surface.call(%{graph: "observed"}, observed: c)
      {:ok, _} = Surface.call(%{graph: "diff"}, declared: @declared, observed: c, window: @window)
      {:ok, _} = Surface.read("connectome://declared", declared: @declared)
      assert {Observed.rows(c), package_terms()} == before
    end
  end

  describe "on the wire, through a host's catalog" do
    defmodule Host do
      @behaviour Catalog
      @collector Module.concat(BeamMCP.Connectome.SurfaceTest, :wire_collector)

      def collector, do: @collector

      @impl true
      def capabilities do
        %{
          tools: [ConnectomeTool.spec()],
          resources: Surface.resources(),
          prompts: []
        }
      end

      @impl true
      def read_resource("connectome://" <> _ = uri) do
        Surface.read(uri,
          declared: [
            server: "fx",
            catalog: Fx.Catalog,
            modules: [Fx.Alpha, Fx.Beta, Fx.Gamma, Fx.MacroOnly, Fx.Dyn, Fx.Catalog],
            tool_modules: %{echo: Fx.Alpha}
          ],
          observed: @collector,
          window: %{"started_at" => "2026-09-14T00:00:00Z", "ended_at" => "2026-09-14T01:00:00Z"}
        )
      end
    end

    setup do
      start_supervised!({Observed, name: Host.collector()}, id: Host.collector())
      :ok
    end

    defp call(state, method, params) do
      {_, r} =
        Server.handle_message(state, %{
          "jsonrpc" => "2.0",
          "id" => 5,
          "method" => method,
          "params" => Map.put(params, "_meta", @modern)
        })

      r
    end

    test "resources/read on connectome://declared carries the export's bytes as the text content" do
      s =
        Server.new(
          catalog: Host,
          dispatch: fn :connectome, args, _ -> Surface.call(args, declared: @declared) end
        )

      r = call(s, "resources/read", %{"uri" => "connectome://declared"})["result"]

      assert [
               %{
                 "uri" => "connectome://declared",
                 "mimeType" => "application/json",
                 "text" => text
               }
             ] = r["contents"]

      assert text == File.read!(@export)
    end

    test "tools/call connectome carries the bytes verbatim in structuredContent with their hash" do
      s =
        Server.new(
          catalog: Host,
          dispatch: fn :connectome, args, _ -> Surface.call(args, declared: @declared) end
        )

      r =
        call(s, "tools/call", %{"name" => "connectome", "arguments" => %{"graph" => "declared"}})[
          "result"
        ]

      assert r["isError"] == false
      assert r["structuredContent"]["bytes"] == File.read!(@export)

      assert r["structuredContent"]["sha256"] ==
               Base.encode16(:crypto.hash(:sha256, File.read!(@export)), case: :lower)
    end

    test "a graph name outside the enum is refused by the tools validator, before the tool runs" do
      s = Server.new(catalog: Host, dispatch: fn _, _, _ -> raise "tool ran" end)

      r =
        call(s, "tools/call", %{"name" => "connectome", "arguments" => %{"graph" => "reach"}})[
          "result"
        ]

      assert r["isError"] == true
    end

    # The tool's own call is a dispatch, and a running collector records every dispatch: after
    # one tools/call connectome the observed graph carries the connectome tool's edge (a review
    # lane measured it). The resource path is not a dispatch and adds nothing. Stated in the
    # moduledoc; pinned here so the consequence is a fact and not a surprise.
    test "the tool observes itself through the collector; the resource path does not" do
      s =
        Server.new(
          catalog: Host,
          dispatch: fn :connectome, args, _ -> Surface.call(args, observed: Host.collector()) end
        )

      before = Observed.rows(Host.collector())
      call(s, "resources/read", %{"uri" => "connectome://observed"})
      assert Observed.rows(Host.collector()) == before
      call(s, "tools/call", %{"name" => "connectome", "arguments" => %{"graph" => "observed"}})
      rows = Observed.rows(Host.collector())

      assert Enum.any?(rows, fn
               {{{:server, _}, {:tool, _, :connectome}, :invoke}, _, _, _} -> true
               _ -> false
             end)
    end

    test "server/discover claims no capability for it" do
      {_, r} =
        Server.handle_message(Server.new(catalog: Host), %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "server/discover"
        })

      assert Map.keys(r["result"]["capabilities"]) == ~w(prompts resources tools)
    end
  end

  # Every persistent term whose key is a module of this package, or a tuple headed by one.
  defp package_terms do
    :persistent_term.get()
    |> Enum.filter(fn
      {key, _} when is_atom(key) ->
        String.starts_with?(Atom.to_string(key), "Elixir.BeamMCP")

      {key, _} when is_tuple(key) and tuple_size(key) > 0 and is_atom(elem(key, 0)) ->
        String.starts_with?(Atom.to_string(elem(key, 0)), "Elixir.BeamMCP")

      _ ->
        false
    end)
    |> Enum.sort()
  end
end
