# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Connectome.ReachTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias BeamMCP.Connectome.{Edge, Graph, Node, Reach}
  alias BeamMCP.Connectome.Reach.Path

  @server "srv"
  @version Graph.schema_version()

  defp id(:srv), do: Node.id({:server, @server})
  defp id(n), do: Node.id({:tool, @server, n})

  defp vertex(:srv), do: Node.new!(kind: :server, level: :server, identity: {:server, @server})
  defp vertex(n), do: Node.new!(kind: :tool, level: :server, identity: {:tool, @server, n})

  defp edge({a, b}), do: edge({a, b, :invoke})

  defp edge({a, b, kind}),
    do: Edge.new!(from: id(a), to: id(b), kind: kind, provenance: :declared)

  defp graph(names, pairs) do
    Graph.new!(
      nodes: Enum.map([:srv | names], &vertex/1),
      edges: Enum.map(pairs, &edge/1),
      schema_version: @version
    )
  end

  # The gate fixture: the only path from the server to x passes g.
  #   srv -> a -> g -> x,  srv -> b -> g
  defp gate_fixture,
    do: graph([:a, :b, :g, :x], [{:srv, :a}, {:srv, :b}, {:a, :g}, {:b, :g}, {:g, :x}])

  # The bypass fixture: the gate fixture plus a -> x, which crosses no gate.
  defp bypass_fixture,
    do: graph([:a, :b, :g, :x], [{:srv, :a}, {:srv, :b}, {:a, :g}, {:b, :g}, {:g, :x}, {:a, :x}])

  describe "the gate fixture" do
    test "x is reachable, g dominates x, and without g x is unreachable" do
      g = gate_fixture()
      assert {:ok, true} = Reach.reachable?(g, id(:srv), id(:x))
      assert {:ok, true} = Reach.dominates?(g, id(:g), id(:x))
      assert {:ok, false} = Reach.reachable_without(g, id(:srv), id(:x), [id(:g)])
    end

    test "the mandatory-pass set of x is every node on the one path, x itself excluded" do
      assert {:ok, set} = Reach.mandatory_pass(gate_fixture(), id(:x))
      assert set == MapSet.new([id(:srv), id(:g)])
    end

    test "a and b are not gates for x: each has the other as a bypass" do
      g = gate_fixture()
      assert {:ok, false} = Reach.dominates?(g, id(:a), id(:x))
      assert {:ok, %Path{}} = Reach.reachable_without(g, id(:srv), id(:x), [id(:a)])
    end
  end

  describe "the bypass fixture" do
    test "adding the bypass edge flips reachable_without to a witness that carries the bypass edge" do
      g = bypass_fixture()

      assert {:ok, %Path{edges: edges} = path} =
               Reach.reachable_without(g, id(:srv), id(:x), [id(:g)])

      assert Enum.any?(edges, &(&1.from == id(:a) and &1.to == id(:x)))
      assert path.nodes == [id(:srv), id(:a), id(:x)]
      refute id(:g) in path.nodes
      assert {:ok, false} = Reach.dominates?(g, id(:g), id(:x))
      assert {:ok, MapSet.new([id(:srv)])} == Reach.mandatory_pass(g, id(:x))
    end
  end

  describe "the witness path is a path in the input graph" do
    property "each consecutive pair is an input edge, from entry to target, crossing no gate" do
      check all({g, gates} <- graph_gen()) do
        case Reach.reachable_without(g, id(:srv), id(:x), gates) do
          {:ok, false} ->
            :ok

          {:ok, %Path{nodes: nodes, edges: edges}} ->
            assert hd(nodes) == id(:srv) and List.last(nodes) == id(:x)
            assert length(edges) == length(nodes) - 1

            for {e, i} <- Enum.with_index(edges) do
              assert e in g.edges
              assert e.from == Enum.at(nodes, i) and e.to == Enum.at(nodes, i + 1)
            end

            assert Enum.all?(nodes, &(&1 not in gates))
        end
      end
    end

    property "mandatory_pass is exactly the set of nodes that dominate x by the removal definition" do
      check all({g, _} <- graph_gen()) do
        case Reach.mandatory_pass(g, id(:x)) do
          {:error, {:unreachable, _}} ->
            assert {:ok, false} = Reach.reachable?(g, id(:srv), id(:x))

          {:ok, set} ->
            for n <- g.nodes, n.id != id(:x) do
              {:ok, dom?} = Reach.dominates?(g, n.id, id(:x))

              assert MapSet.member?(set, n.id) == dom?,
                     "#{n.id}: in set #{MapSet.member?(set, n.id)}, dominates #{dom?}"
            end
        end
      end
    end
  end

  describe "constraints" do
    test "an edge-kind constraint traverses only the kinds named" do
      g = graph([:a, :x], [{:srv, :a, :invoke}, {:a, :x, :read}])
      assert {:ok, true} = Reach.reachable?(g, id(:srv), id(:x))
      assert {:ok, false} = Reach.reachable?(g, id(:srv), id(:x), kinds: [:invoke])
      assert {:ok, true} = Reach.reachable?(g, id(:srv), id(:x), kinds: [:invoke, :read])
    end

    test "max_hops bounds the witness" do
      g = graph([:a, :b, :x], [{:srv, :a}, {:a, :b}, {:b, :x}])
      assert {:ok, true} = Reach.reachable?(g, id(:srv), id(:x), max_hops: 3)
      assert {:ok, false} = Reach.reachable?(g, id(:srv), id(:x), max_hops: 2)
    end

    test "the entry set is the server nodes unless given" do
      g = graph([:a, :x], [{:a, :x}])
      assert {:error, {:unreachable, _}} = Reach.mandatory_pass(g, id(:x))
      assert {:ok, MapSet.new([id(:a)])} == Reach.mandatory_pass(g, id(:x), entries: [id(:a)])
    end
  end

  describe "refusals, by name" do
    test "a graph over the edge cap is refused, and the refusal names the cap" do
      g = gate_fixture()
      assert {:error, {:cap, :max_edges, 3}} = Reach.reachable?(g, id(:srv), id(:x), max_edges: 3)
      assert {:error, {:cap, :max_edges, 3}} = Reach.mandatory_pass(g, id(:x), max_edges: 3)
    end

    test "all-paths enumeration is refused by name, not attempted" do
      assert {:error, {:refused, :all_paths}} = Reach.all_paths(gate_fixture(), id(:srv), id(:x))
    end

    test "an unknown node, gate or entry is refused by name" do
      g = gate_fixture()

      assert {:error, {:unknown_node, "srv/tool/zz"}} =
               Reach.reachable?(g, id(:srv), "srv/tool/zz")

      assert {:error, {:unknown_node, "nope"}} =
               Reach.reachable_without(g, id(:srv), id(:x), ["nope"])

      assert {:error, {:unknown_node, "nope"}} =
               Reach.mandatory_pass(g, id(:x), entries: ["nope"])
    end

    test "an unknown or malformed option is refused by name" do
      g = gate_fixture()
      assert {:error, {:unknown_option, :hops}} = Reach.reachable?(g, id(:srv), id(:x), hops: 1)

      assert {:error, {:invalid, :max_hops, -1}} =
               Reach.reachable?(g, id(:srv), id(:x), max_hops: -1)

      assert {:error, {:invalid, :kinds, [:fly]}} =
               Reach.reachable?(g, id(:srv), id(:x), kinds: [:fly])
    end
  end

  # Random graphs over eight tool names, always with a server and an x; gates drawn from the
  # tools other than x.
  defp graph_gen do
    names = [:a, :b, :c, :d, :e, :f]

    gen all(
          pairs <- list_of({member_of([:srv | names]), member_of(names ++ [:x])}, max_length: 14),
          kinds <- list_of(member_of([:invoke, :read, :message]), length: length(pairs)),
          gates <- list_of(member_of(names), max_length: 3)
        ) do
      edges =
        pairs
        |> Enum.zip(kinds)
        |> Enum.map(fn {{a, b}, k} -> {a, b, k} end)
        |> Enum.uniq_by(fn {a, b, k} -> {a, b, k} end)

      {graph(names ++ [:x], edges), Enum.uniq(Enum.map(gates, &id/1))}
    end
  end
end
