# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Connectome.GraphTest do
  use ExUnit.Case, async: true

  alias BeamMCP.Connectome.{Edge, Graph, Node}

  @version Graph.schema_version()

  defp node!(kind, name) do
    Node.new!(kind: kind, level: :server, identity: {kind, "srv", name})
  end

  defp fixture do
    server = Node.new!(kind: :server, level: :server, identity: {:server, "srv"})
    tools = for n <- [:echo, :add, :list, :read, :write], do: node!(:tool, n)
    resources = for n <- ["r://a", "r://b"], do: node!(:resource, n)
    nodes = [server | tools ++ resources]

    edges =
      for t <- tools do
        Edge.new!(from: server.id, to: t.id, kind: :invoke, provenance: :declared)
      end ++
        for r <- resources, t <- Enum.take(tools, 2) do
          Edge.new!(from: t.id, to: r.id, kind: :read, provenance: :observed, weight: 2)
        end

    {nodes, edges}
  end

  describe "Graph.new/1" do
    test "builds a graph with nodes and edges in canonical order" do
      {nodes, edges} = fixture()
      assert {:ok, %Graph{} = g} = Graph.new(nodes: nodes, edges: edges, schema_version: @version)
      assert g.schema_version == @version
      assert Enum.map(g.nodes, & &1.id) == Enum.sort(Enum.map(nodes, & &1.id))
      assert Enum.map(g.edges, &Edge.key/1) == Enum.sort(Enum.map(edges, &Edge.key/1))
    end

    test "property: a graph built from shuffled lists equals one built from ordered lists" do
      {nodes, edges} = fixture()
      {:ok, ordered} = Graph.new(nodes: nodes, edges: edges, schema_version: @version)

      for _ <- 1..25 do
        {:ok, shuffled} =
          Graph.new(
            nodes: Enum.shuffle(nodes),
            edges: Enum.shuffle(edges),
            schema_version: @version
          )

        assert shuffled == ordered
      end
    end

    test "schema_version is required" do
      {nodes, edges} = fixture()
      assert {:error, {:missing, :schema_version}} = Graph.new(nodes: nodes, edges: edges)
    end

    test "a schema_version this slice does not define is refused by value" do
      {nodes, edges} = fixture()

      assert {:error, {:invalid, :schema_version, 99}} =
               Graph.new(nodes: nodes, edges: edges, schema_version: 99)
    end

    test "an unknown key is refused by name" do
      {nodes, edges} = fixture()

      assert {:error, {:unknown_key, :signed_by}} =
               Graph.new(nodes: nodes, edges: edges, schema_version: @version, signed_by: "me")
    end

    test "a duplicate node id is refused by id" do
      {nodes, edges} = fixture()
      dup = hd(nodes)

      assert {:error, {:duplicate_node, id}} =
               Graph.new(nodes: [dup | nodes], edges: edges, schema_version: @version)

      assert id == dup.id
    end

    test "a duplicate edge key is refused by key" do
      {nodes, edges} = fixture()
      dup = hd(edges)

      assert {:error, {:duplicate_edge, key}} =
               Graph.new(nodes: nodes, edges: [dup | edges], schema_version: @version)

      assert key == Edge.key(dup)
    end

    test "an edge whose endpoint is not a node is refused as dangling" do
      {nodes, edges} = fixture()
      ghost = Node.id({:tool, "srv", :ghost})
      {:ok, e} = Edge.new(from: ghost, to: hd(nodes).id, kind: :invoke, provenance: :declared)

      assert {:error, {:dangling_edge, ^ghost}} =
               Graph.new(nodes: nodes, edges: [e | edges], schema_version: @version)
    end

    test "nodes and edges must be lists of the structs, not bare maps" do
      assert {:error, {:invalid, :nodes, [%{id: "x"}]}} =
               Graph.new(nodes: [%{id: "x"}], edges: [], schema_version: @version)

      assert {:error, {:invalid, :edges, [:e]}} =
               Graph.new(nodes: [], edges: [:e], schema_version: @version)
    end

    test "an empty graph is a graph" do
      assert {:ok, %Graph{nodes: [], edges: []}} =
               Graph.new(nodes: [], edges: [], schema_version: @version)
    end

    test "new!/1 raises the same named reason, and returns the graph otherwise" do
      assert_raise ArgumentError, ~r/\{:missing, :schema_version\}/, fn ->
        Graph.new!(nodes: [], edges: [])
      end

      assert %Graph{nodes: [], edges: []} =
               Graph.new!(nodes: [], edges: [], schema_version: @version)
    end
  end

  describe "the sign slot, observed from outside" do
    test "every edge a graph holds carries :unknown, whatever the input order" do
      {nodes, edges} = fixture()

      {:ok, g} =
        Graph.new(
          nodes: Enum.reverse(nodes),
          edges: Enum.reverse(edges),
          schema_version: @version
        )

      assert Enum.all?(g.edges, &(&1.sign == :unknown))
    end
  end
end
