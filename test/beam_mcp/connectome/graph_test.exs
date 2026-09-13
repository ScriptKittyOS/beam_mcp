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
    test "every edge the package builds carries :unknown, whatever the input order" do
      {nodes, edges} = fixture()

      {:ok, g} =
        Graph.new(
          nodes: Enum.reverse(nodes),
          edges: Enum.reverse(edges),
          schema_version: @version
        )

      assert Enum.all?(g.edges, &(&1.sign == :unknown))
    end

    test "a sign a host wrote on its own copy survives Graph.new/1 untouched -- the package launders nothing" do
      # Written here, outside lib/, which is the only place a sign other than :unknown may be
      # written. Erasing a host's :deny would itself be an authority act.
      {nodes, edges} = fixture()
      [first | rest] = edges
      signed = %{first | sign: :deny}
      {:ok, g} = Graph.new(nodes: nodes, edges: [signed | rest], schema_version: @version)
      assert Enum.find(g.edges, &(Edge.key(&1) == Edge.key(first))).sign == :deny
    end

    test "two edges differing only in sign are the same edge" do
      {nodes, edges} = fixture()
      [first | _] = edges

      assert {:error, {:duplicate_edge, key}} =
               Graph.new(
                 nodes: nodes,
                 edges: [%{first | sign: :allow} | edges],
                 schema_version: @version
               )

      assert key == Edge.key(first)
    end
  end

  describe "host-built structs are validated, never modified" do
    # A host may hand-build a %Node{} or %Edge{} and bypass the constructors. A later slice
    # hashes whatever this function accepted, so a malformed struct would become a hash over
    # garbage. Field domains are checked and refused by name; nothing is normalised, coerced,
    # defaulted or rewritten. Validation is reading; laundering is writing.
    test "an edge with a sign outside the vocabulary is refused, not corrected to :unknown" do
      {nodes, edges} = fixture()
      [first | rest] = edges

      assert {:error, {:invalid, :sign, :approve}} =
               Graph.new(
                 nodes: nodes,
                 edges: [%{first | sign: :approve} | rest],
                 schema_version: @version
               )
    end

    test "an edge with a kind, provenance, weight or endpoint outside its domain is refused by field" do
      {nodes, edges} = fixture()
      [first | rest] = edges

      for {field, value} <- [
            kind: :teleport,
            provenance: :guessed,
            weight: -1,
            weight: "3",
            from: :srv,
            to: 7
          ] do
        assert {:error, {:invalid, ^field, ^value}} =
                 Graph.new(
                   nodes: nodes,
                   edges: [Map.put(first, field, value) | rest],
                   schema_version: @version
                 )
      end
    end

    test "a node with a kind, level, id or labels outside its domain is refused by field" do
      {nodes, edges} = fixture()
      [first | rest] = nodes

      for {field, value} <- [kind: :neuron, level: :neuropil, id: :not_a_string, labels: [:a]] do
        assert {:error, {:invalid, ^field, ^value}} =
                 Graph.new(
                   nodes: [Map.put(first, field, value) | rest],
                   edges: edges,
                   schema_version: @version
                 )
      end
    end

    test "a well-formed host-built struct is held exactly as given" do
      {nodes, edges} = fixture()

      hand = %Node{
        id: Node.id({:tool, "srv", :hand}),
        kind: :tool,
        level: :server,
        labels: %{mode: :proposal}
      }

      {:ok, g} = Graph.new(nodes: [hand | nodes], edges: edges, schema_version: @version)
      assert Enum.find(g.nodes, &(&1.id == hand.id)) == hand
    end
  end

  test "options that are not a keyword list are refused by name, not by a clause error" do
    assert {:error, {:invalid, :opts, %{}}} = Graph.new(%{})
    assert_raise ArgumentError, ~r/\{:invalid, :opts, :nope\}/, fn -> Graph.new!(:nope) end
  end
end
