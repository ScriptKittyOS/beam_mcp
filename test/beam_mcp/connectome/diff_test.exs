# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Connectome.DiffTest do
  @moduledoc """
  The diff engine: a declared graph and an observed graph into four edge classes and a
  coverage bound, as a record with canonical bytes.

  The matching is on the edge's label -- from, to, kind -- because ids are structural, so
  two edges are the same edge iff their labels are equal; there is no isomorphism anywhere,
  and the first test says so in its name so nobody "improves" the diff into one later.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias BeamMCP.Connectome.{Canonical, Diff, Edge, Graph, Node, Observed}
  alias BeamMCP.Fixture.ObservedCatalog, as: Catalog
  alias BeamMCP.Server

  @server "srv"
  @version Graph.schema_version()
  @window %{"started_at" => "2026-09-14T00:00:00Z", "ended_at" => "2026-09-14T01:00:00Z"}
  @marker "PAYLOAD-MARKER-d1ff"

  defp srv, do: Node.new!(kind: :server, level: :server, identity: {:server, @server})
  defp tool(n), do: Node.new!(kind: :tool, level: :server, identity: {:tool, @server, n})
  defp id(n), do: Node.id({:tool, @server, n})

  # The sign slot is the host's: there is no setter, a host writes the struct field (010
  # pins that a host's sign survives Graph.new/1).
  defp edge(from, to, prov, opts \\ []) do
    {sign, opts} = Keyword.pop(opts, :sign, :unknown)

    edge =
      Edge.new!(
        Keyword.merge(
          [from: id(from), to: id(to), kind: :invoke, provenance: prov],
          opts
        )
      )

    %{edge | sign: sign}
  end

  defp graph(nodes, edges),
    do: Graph.new!(nodes: nodes, edges: edges, schema_version: @version)

  # The crafted pair: one edge in each class and nothing unclassified.
  #
  #   a -> b   declared and observed, signs unknown on both       -> declared_and_observed
  #   a -> c   declared only                                       -> declared_never_observed
  #   b -> c   observed only                                       -> observed_but_undeclared
  #   c -> a   both, declared :allow, observed :deny               -> changed_sign
  #   b -> a   both, declared :allow, observed :unknown -- a sign the consumer did not supply
  #            on both sides is not a change                      -> declared_and_observed
  defp crafted do
    nodes = [srv(), tool(:a), tool(:b), tool(:c)]

    declared =
      graph(nodes, [
        edge(:a, :b, :declared),
        edge(:a, :c, :declared),
        edge(:c, :a, :declared, sign: :allow),
        edge(:b, :a, :declared, sign: :allow)
      ])

    # The observed side has never seen tool c as a node of its own -- only as an endpoint.
    observed =
      graph([srv(), tool(:a), tool(:b), tool(:c)], [
        edge(:a, :b, :observed, weight: 3),
        edge(:b, :c, :observed, weight: 1),
        edge(:c, :a, :observed, weight: 2, sign: :deny),
        edge(:b, :a, :observed, weight: 1)
      ])

    {declared, observed}
  end

  describe "the four classes, on labels and never on isomorphism" do
    test "a crafted pair yields exactly one edge in each class, and nothing unclassified" do
      {declared, observed} = crafted()
      assert {:ok, %Diff{} = diff} = Diff.run(declared, observed, window: @window)

      assert diff.classes.declared_and_observed ==
               Enum.sort([
                 %{from: id(:a), to: id(:b), kind: :invoke},
                 %{from: id(:b), to: id(:a), kind: :invoke}
               ])

      assert diff.classes.declared_never_observed == [%{from: id(:a), to: id(:c), kind: :invoke}]
      assert diff.classes.observed_but_undeclared == [%{from: id(:b), to: id(:c), kind: :invoke}]

      assert diff.classes.changed_sign == [
               %{
                 from: id(:c),
                 to: id(:a),
                 kind: :invoke,
                 declared_sign: :allow,
                 observed_sign: :deny
               }
             ]

      # Nothing unclassified: every label of either side is in exactly one class.
      labels = fn g -> Enum.map(g.edges, &%{from: &1.from, to: &1.to, kind: &1.kind}) end
      all = Enum.uniq(labels.(declared) ++ labels.(observed))

      classified =
        Enum.flat_map(
          Map.values(diff.classes),
          &Enum.map(&1, fn e -> Map.take(e, [:from, :to, :kind]) end)
        )

      assert Enum.sort(classified) == Enum.sort(all)
      assert length(classified) == length(Enum.uniq(classified))
    end

    test "the window is the consumer's, required, and carried verbatim; it is never inferred" do
      {declared, observed} = crafted()
      assert {:error, {:missing, :window}} = Diff.run(declared, observed, [])
      assert {:ok, diff} = Diff.run(declared, observed, window: @window)
      assert diff.window == @window
    end

    test "a graph a literal built wrong is refused by name before it is compared" do
      {declared, observed} = crafted()
      bad = %Graph{declared | nodes: [%Node{id: "x", kind: :neuron, level: :y}]}

      assert {:error, {:declared, {:invalid, :kind, :neuron}}} =
               Diff.run(bad, observed, window: @window)

      assert {:error, {:observed, {:invalid, :kind, :neuron}}} =
               Diff.run(declared, bad, window: @window)
    end
  end

  describe "the coverage bound, as counts a consumer divides" do
    test "the counts match a hand computation on the crafted pair" do
      {declared, observed} = crafted()
      {:ok, diff} = Diff.run(declared, observed, window: @window)

      # By hand: declared edges 4 (a->b, a->c, c->a, b->a); observed edges 4 (a->b, b->c,
      # c->a, b->a); labels in both 3 (a->b, c->a, b->a); declared nodes 4 (srv, a, b, c);
      # observed nodes 4; nodes in both 4; declared edges whose both endpoints are observed
      # nodes: all 4 (a, b, c are all observed nodes).
      assert diff.coverage == %{
               declared_edges: 4,
               observed_edges: 4,
               declared_and_observed: 3,
               declared_endpoint_covered: 4,
               declared_nodes: 4,
               observed_nodes: 4,
               nodes_in_both: 4
             }
    end

    test "an endpoint the observed side never saw as a node lowers the completeness count and nothing else" do
      # Declared d -> e where the observed graph has neither node: the edge is dead authority
      # AND not endpoint-covered. Counts are integers; the fractions are the consumer's.
      {declared, observed} = crafted()

      declared =
        graph(declared.nodes ++ [tool(:d), tool(:e)], declared.edges ++ [edge(:d, :e, :declared)])

      {:ok, diff} = Diff.run(declared, observed, window: @window)
      assert diff.coverage.declared_edges == 5
      assert diff.coverage.declared_endpoint_covered == 4
      assert diff.coverage.declared_nodes == 6
      assert diff.coverage.nodes_in_both == 4
      assert %{from: from} = List.last(diff.classes.declared_never_observed)
      assert from in [id(:a), id(:d)]
    end
  end

  describe "canonical bytes" do
    test "identical inputs give identical bytes, whatever the order the lists were built in" do
      {declared, observed} = crafted()
      {:ok, a} = Diff.run(declared, observed, window: @window)

      shuffled = fn g ->
        graph(Enum.reverse(g.nodes), Enum.reverse(g.edges))
      end

      {:ok, b} = Diff.run(shuffled.(declared), shuffled.(observed), window: @window)
      assert Diff.encode!(a) == Diff.encode!(b)
      assert Diff.hash!(a) == Diff.hash!(b)
      assert byte_size(Diff.hash!(a)) == 32
    end

    test "the bytes are the 012 encoder's over the record: the label grammar, key order by UTF-16, atoms under their field names" do
      {declared, observed} = crafted()
      {:ok, diff} = Diff.run(declared, observed, window: @window)
      bytes = Diff.encode!(diff)

      # The same writer, called on the record as a plain map, gives the same bytes.
      assert {:ok, ^bytes} = Canonical.encode_value(Diff.to_record(diff))

      assert String.starts_with?(
               bytes,
               ~s({"classes":{"changed_sign":[{"declared_sign":"allow","from":")
             )

      assert bytes =~ ~s("schema_version":1)

      assert bytes =~
               ~s("window":{"ended_at":"2026-09-14T01:00:00Z","started_at":"2026-09-14T00:00:00Z"})

      # No bare atom, no float, nothing but the record.
      refute bytes =~ ":invoke"
      refute bytes =~ "0."
    end

    test "a window with no canonical bytes is refused by name" do
      {declared, observed} = crafted()
      assert {:error, {:uncanonical, _}} = Diff.run(declared, observed, window: %{ratio: 0.5})
    end

    test "encode_value/1 writes any label-shaped value with the page's rules, and refuses the rest by name" do
      assert {:ok, ~s({"a":[1,"café"],"b":{"k":"v"},"z":true})} =
               Canonical.encode_value(%{"b" => %{k: :v}, z: true, a: [1, "cafe\u0301"]})

      assert {:error, {:uncanonical, _}} = Canonical.encode_value([1, 2])
      assert {:error, {:uncanonical, _}} = Canonical.encode_value(%{f: 1.5})
      assert {:error, {:uncanonical, _}} = Canonical.encode_value(%{t: {1, 2}})
      assert {:error, {:uncanonical, _}} = Canonical.encode_value(%{"é" => 1, "e\u0301" => 2})
    end
  end

  describe "edge identity only, extended to the diff" do
    test "an observed graph the collector built from a call carrying a marker diffs to bytes with no marker" do
      name = :"#{__MODULE__}.c#{System.unique_integer([:positive])}"
      _ = start_supervised!({Observed, name: name})

      state =
        Server.new(dispatch: fn _, _, _ -> {:ok, %{}} end, catalog: Catalog, server_name: @server)

      {_, %{"result" => _}} =
        Server.handle_message(state, %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "tools/call",
          "params" => %{"name" => "echo", "arguments" => %{"k" => @marker}}
        })

      {:ok, observed} = Observed.snapshot(name)
      assert observed.edges != []
      declared = graph([srv()], [])
      {:ok, diff} = Diff.run(declared, observed, window: @window)
      bytes = Diff.encode!(diff)
      refute bytes =~ @marker
      refute inspect(diff, limit: :infinity, printable_limit: :infinity) =~ @marker
      # The collector's graph holds the call's edge and whatever else the dispatch produced;
      # all of it is undeclared here, and none of it carries the marker.
      assert diff.classes.observed_but_undeclared != []
      assert diff.classes.declared_and_observed == [] and diff.classes.changed_sign == []
    end
  end

  describe "properties" do
    property "every edge of either input lands in exactly one class, and the classes partition the label union" do
      check all({declared, observed} <- pair_gen()) do
        {:ok, diff} = Diff.run(declared, observed, window: @window)
        take = &Map.take(&1, [:from, :to, :kind])
        classified = Enum.flat_map(Map.values(diff.classes), &Enum.map(&1, take))
        labels = fn g -> Enum.map(g.edges, &%{from: &1.from, to: &1.to, kind: &1.kind}) end
        union = Enum.uniq(labels.(declared) ++ labels.(observed))
        assert Enum.sort(classified) == Enum.sort(union)
        assert length(classified) == length(Enum.uniq(classified))

        assert diff.coverage.declared_edges == length(declared.edges)
        assert diff.coverage.observed_edges == length(observed.edges)

        # The count of labels in both is the two "in both" classes together.
        assert diff.coverage.declared_and_observed ==
                 length(diff.classes.declared_and_observed) + length(diff.classes.changed_sign)
      end
    end
  end

  defp pair_gen do
    gen all(
          # A subset of five names, drawn without a uniqueness generator (a five-term space
          # makes stream_data give up on uniqueness at small sizes).
          picks <- list_of(boolean(), length: 5),
          names = [:a | for({n, true} <- Enum.zip([:b, :c, :d, :e, :f], picks), do: n)],
          d_pairs <-
            list_of({member_of(names), member_of(names), member_of([:allow, :deny, :unknown])},
              max_length: 8
            ),
          o_pairs <-
            list_of({member_of(names), member_of(names), member_of([:allow, :deny, :unknown])},
              max_length: 8
            )
        ) do
      nodes = [srv() | Enum.map(names, &tool/1)]

      build = fn pairs, prov ->
        pairs
        |> Enum.map(fn {a, b, s} -> edge(a, b, prov, sign: s) end)
        |> Enum.uniq_by(&Edge.key/1)
      end

      {graph(nodes, build.(d_pairs, :declared)), graph(nodes, build.(o_pairs, :observed))}
    end
  end
end
