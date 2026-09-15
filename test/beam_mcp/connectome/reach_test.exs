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

  describe "two shapes Lengauer-Tarjan gets wrong when broken (shrunk by the oracle property)" do
    # Found by the oracle at 20 000 generations against two mutants the suite's 100 did not
    # reach; pinned here so the kill is deterministic. Each names the node the broken
    # algorithm wrongly puts in the set and the path that goes round it.
    test "step 4 (implicit to explicit dominators): f is not a dominator of x, srv->c->b->x goes round it" do
      g =
        graph([:a, :b, :c, :f, :x], [
          {:srv, :a},
          {:srv, :c},
          {:a, :f},
          {:b, :x},
          {:c, :b},
          {:c, :f},
          {:f, :x}
        ])

      assert {:ok, MapSet.new([id(:srv)])} == Reach.mandatory_pass(g, id(:x))
      assert {:ok, false} = Reach.dominates?(g, id(:f), id(:x))
    end

    test "path compression: e is not a dominator of x, srv->d->b->a->x goes round it" do
      g =
        graph([:a, :b, :d, :e, :x], [
          {:srv, :d},
          {:srv, :e},
          {:a, :x},
          {:b, :a},
          {:d, :b},
          {:e, :a}
        ])

      assert {:ok, MapSet.new([id(:srv), id(:a)])} == Reach.mandatory_pass(g, id(:x))
      assert {:ok, false} = Reach.dominates?(g, id(:e), id(:x))
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

    test "a witness under a kind constraint carries edges of the admitted kinds only" do
      g =
        graph([:a, :x], [
          {:srv, :a, :invoke},
          {:srv, :a, :read},
          {:a, :x, :read},
          {:a, :x, :invoke}
        ])

      assert {:ok, %Path{edges: edges}} =
               Reach.reachable_without(g, id(:srv), id(:x), [], kinds: [:read])

      assert Enum.map(edges, & &1.kind) == [:read, :read]
    end

    test "a node reaches itself in zero hops, with or without a cycle" do
      g = graph([:a, :x], [{:srv, :a}])
      assert {:ok, true} = Reach.reachable?(g, id(:x), id(:x))

      assert {:ok, %Path{nodes: [_], edges: []}} =
               Reach.reachable_without(g, id(:x), id(:x), [id(:a)])
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

  describe "what round 1 found: an option that cannot bear on the question is refused, not read" do
    # Both lanes, independently: with max_hops: 4 the module handed back a gate-free four-hop
    # witness round g and, in the same breath, said g dominates x -- and the root's own edge
    # counted as a hop. Bounded-length dominance is not the question Lengauer-Tarjan answers.
    test "max_hops is refused by name on the two entry-set questions" do
      g =
        graph([:a, :b, :c, :g, :x], [
          {:srv, :g},
          {:g, :x},
          {:srv, :a},
          {:a, :b},
          {:b, :c},
          {:c, :x}
        ])

      assert {:ok, %Path{nodes: nodes}} =
               Reach.reachable_without(g, id(:srv), id(:x), [id(:g)], max_hops: 4)

      assert length(nodes) == 5

      assert {:error, {:unknown_option, :max_hops}} =
               Reach.dominates?(g, id(:g), id(:x), max_hops: 4)

      assert {:error, {:unknown_option, :max_hops}} = Reach.mandatory_pass(g, id(:x), max_hops: 3)
      # And without it the two dominance answers agree with the witness: g is not a gate.
      assert {:ok, false} = Reach.dominates?(g, id(:g), id(:x))
      assert {:ok, MapSet.new([id(:srv)])} == Reach.mandatory_pass(g, id(:x))
    end

    test "entries is refused by name on the two path questions" do
      g = gate_fixture()

      assert {:error, {:unknown_option, :entries}} =
               Reach.reachable?(g, id(:srv), id(:x), entries: [id(:a)])

      assert {:error, {:unknown_option, :entries}} =
               Reach.reachable_without(g, id(:srv), id(:x), [], entries: [id(:a)])
    end

    test "a graph with no server node and no entries given is refused by name, not answered unreachable" do
      g = graph([:a, :x], [{:a, :x}])
      g = %{g | nodes: Enum.reject(g.nodes, &(&1.kind == :server))}
      assert {:error, {:invalid, :entries, []}} = Reach.mandatory_pass(g, id(:x))
      assert {:error, {:invalid, :entries, []}} = Reach.dominates?(g, id(:a), id(:x))
    end

    test "a literal graph Graph.check/1 would refuse is refused with its reason, not answered" do
      g = gate_fixture()

      dangling =
        Edge.new!(from: id(:x), to: "srv/tool/nowhere", kind: :invoke, provenance: :declared)

      literal = %{g | edges: g.edges ++ [dangling]}

      assert {:error, {:invalid_graph, {:dangling_edge, "srv/tool/nowhere"}}} =
               Reach.reachable?(literal, id(:srv), id(:x))

      assert {:error, {:invalid_graph, _}} = Reach.mandatory_pass(literal, id(:x))
    end
  end

  describe "three page claims, pinned" do
    test "from == to with both among the gates is false, never a one-node witness that crosses a gate" do
      g = gate_fixture()
      assert {:ok, false} = Reach.reachable_without(g, id(:g), id(:g), [id(:g)])
    end

    test "a reachable target dominates itself" do
      assert {:ok, true} = Reach.dominates?(gate_fixture(), id(:x), id(:x))
    end

    property "the witness is a shortest gate-free path: its hop count is the breadth-first distance" do
      check all({g, gates} <- graph_gen()) do
        case Reach.reachable_without(g, id(:srv), id(:x), gates) do
          {:ok, false} ->
            assert bfs_distance(g, id(:srv), id(:x), gates) == :none

          {:ok, %Path{edges: edges}} ->
            assert length(edges) == bfs_distance(g, id(:srv), id(:x), gates)
        end
      end
    end
  end

  # An independent breadth-first distance over the graph's edge list, gates removed.
  defp bfs_distance(g, from, to, gates) do
    blocked = MapSet.new(gates)

    if from in blocked or to in blocked,
      do: :none,
      else: bfs(g, [{from, 0}], MapSet.new([from]), to, blocked)
  end

  defp bfs(_g, [], _seen, _to, _blocked), do: :none
  defp bfs(_g, [{to, d} | _], _seen, to, _blocked), do: d

  defp bfs(g, [{v, d} | rest], seen, to, blocked) do
    next =
      for e <- g.edges,
          e.from == v,
          not MapSet.member?(seen, e.to),
          not MapSet.member?(blocked, e.to),
          do: e.to

    next = Enum.uniq(next)

    bfs(
      g,
      rest ++ Enum.map(next, &{&1, d + 1}),
      Enum.reduce(next, seen, &MapSet.put(&2, &1)),
      to,
      blocked
    )
  end

  describe "refusals, by name" do
    test "a graph over the edge cap is refused, and the refusal names the cap" do
      g = gate_fixture()
      assert {:error, {:cap, :max_edges, 3}} = Reach.reachable?(g, id(:srv), id(:x), max_edges: 3)
      # The cap is inclusive: a graph of exactly max_edges edges is not over it.
      assert {:ok, true} = Reach.reachable?(g, id(:srv), id(:x), max_edges: length(g.edges))
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

  # Random graphs over six tool names and x, always with a server; gates drawn from the
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
