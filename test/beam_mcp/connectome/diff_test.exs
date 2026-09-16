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
  @signs [:allow, :deny, :hold, :ungoverned, :unset]
  @marker "PAYLOAD-MARKER-d1ff"

  defp srv, do: Node.new!(kind: :server, level: :server, identity: {:server, @server})
  defp tool(n), do: Node.new!(kind: :tool, level: :server, identity: {:tool, @server, n})
  defp id(n), do: Node.id({:tool, @server, n})

  # The sign slot is the host's: there is no setter, a host writes the struct field (010
  # pins that a host's sign survives Graph.new/1).
  defp edge(from, to, prov, opts \\ []) do
    {sign, opts} = Keyword.pop(opts, :sign, :unset)

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
  #   b -> a   both, declared :allow, observed :unset -- a sign the consumer did not supply
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

    test "the kind is part of the label: the same from and to under two kinds are two labels, on both sides" do
      # A review lane dropped the kind from the label in a scratchpad copy and every test
      # still passed: every edge in this file was :invoke. Two kinds on both sides are two
      # labels in both; one kind moved to the other side is one dead and one drift.
      nodes = [srv(), tool(:a), tool(:b)]
      both = fn prov -> [edge(:a, :b, prov), edge(:a, :b, prov, kind: :read)] end

      {:ok, diff} =
        Diff.run(graph(nodes, both.(:declared)), graph(nodes, both.(:observed)), window: @window)

      assert length(diff.classes.declared_and_observed) == 2
      assert diff.coverage.declared_edges == 2 and diff.coverage.declared_and_observed == 2

      {:ok, diff} =
        Diff.run(
          graph(nodes, [edge(:a, :b, :declared)]),
          graph(nodes, [edge(:a, :b, :observed, kind: :read)]),
          window: @window
        )

      assert [%{kind: :invoke}] = diff.classes.declared_never_observed
      assert [%{kind: :read}] = diff.classes.observed_but_undeclared
      assert diff.classes.declared_and_observed == []
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

  describe "labels are compared as the encoder writes them: after NFC, one provenance per graph" do
    # A consumer lane rebuilt the record from the page and diverged on exactly this: it read
    # rule 6 (strings are NFC before anything else) and normalised before comparing; the code
    # compared raw, gave two classes for one label, and accepted a graph the encoder refuses.
    test "ids that coincide after NFC across the two graphs are one label, and the record carries it once" do
      composed = Node.new!(kind: :tool, level: :server, identity: {:tool, @server, :"\u00E9"})
      decomposed = Node.new!(kind: :tool, level: :server, identity: {:tool, @server, :"e\u0301"})
      refute composed.id == decomposed.id
      assert String.normalize(composed.id, :nfc) == String.normalize(decomposed.id, :nfc)

      declared =
        graph([srv(), tool(:a), composed], [
          %{edge(:a, :a, :declared) | to: composed.id, sign: :allow}
        ])

      observed =
        graph([srv(), tool(:a), decomposed], [
          %{edge(:a, :a, :observed) | to: decomposed.id, sign: :deny}
        ])

      {:ok, diff} = Diff.run(declared, observed, window: @window)

      assert [%{to: to, declared_sign: :allow, observed_sign: :deny}] = diff.classes.changed_sign
      assert to == String.normalize(composed.id, :nfc)

      assert diff.classes.declared_never_observed == [] and
               diff.classes.observed_but_undeclared == []

      assert diff.coverage == %{
               declared_edges: 1,
               observed_edges: 1,
               declared_and_observed: 1,
               declared_endpoint_covered: 1,
               observed_endpoint_declared: 1,
               declared_nodes: 3,
               observed_nodes: 3,
               nodes_in_both: 3,
               declared_sign_only: 0,
               observed_sign_only: 0
             }

      bytes = Diff.encode!(diff)
      assert length(String.split(bytes, "srv/tool/\u00E9")) == 2
    end

    test "a graph whose ids coincide after NFC has no canonical bytes, and so no diff: refused by name" do
      composed = Node.new!(kind: :tool, level: :server, identity: {:tool, @server, :"\u00E9"})
      decomposed = Node.new!(kind: :tool, level: :server, identity: {:tool, @server, :"e\u0301"})
      twins = graph([srv(), composed, decomposed], [])
      {declared, observed} = crafted()

      assert {:error, {:declared, {:uncanonical, {:duplicate_id_after_nfc, _}}}} =
               Diff.run(twins, observed, window: @window)

      assert {:error, {:observed, {:uncanonical, {:duplicate_id_after_nfc, _}}}} =
               Diff.run(declared, twins, window: @window)
    end

    test "a graph carrying the other side's provenance is refused by name, so edges and labels coincide" do
      {declared, observed} = crafted()
      mixed = graph(declared.nodes, declared.edges ++ [edge(:a, :b, :observed, weight: 1)])

      assert {:error, {:declared, {:invalid, :provenance, :observed}}} =
               Diff.run(mixed, observed, window: @window)

      assert {:error, {:observed, {:invalid, :provenance, :declared}}} =
               Diff.run(declared, mixed, window: @window)
    end

    test "the options are a keyword list, refused by name otherwise; the hash is also given as hex" do
      {declared, observed} = crafted()
      assert {:error, {:invalid, :opts, %{}}} = Diff.run(declared, observed, %{window: @window})
      # An option run/3 does not take is refused by name, as Server.new/1 refuses one.
      assert {:error, {:invalid, :opts, [:windw]}} = Diff.run(declared, observed, windw: @window)

      assert {:error, {:invalid, :opts, [:other]}} =
               Diff.run(declared, observed, window: @window, other: 1)

      {:ok, diff} = Diff.run(declared, observed, window: @window)
      assert {:ok, hex} = Diff.hash_hex(diff)
      assert hex == Base.encode16(Diff.hash!(diff), case: :lower) and Diff.hash_hex!(diff) == hex
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
      # ... and observed edges whose both endpoints are declared nodes: all 4 (a, b, c are
      # all declared nodes) -- the completeness figure with the connectomics roles kept.
      # The two one-sided sign counts (016d): of the three labels in both, b->a carries a
      # sign on the declared side (allow) and none on the observed (unset) -- 1 declared
      # only; c->a carries one on each (allow, deny: changed-sign, not one-sided); a->b none
      # on either. Nothing is signed on the observed side only -- 0.
      assert diff.coverage == %{
               declared_edges: 4,
               observed_edges: 4,
               declared_and_observed: 3,
               declared_endpoint_covered: 4,
               observed_endpoint_declared: 4,
               declared_nodes: 4,
               observed_nodes: 4,
               nodes_in_both: 4,
               declared_sign_only: 1,
               observed_sign_only: 0
             }
    end

    # 016d: a sign present on one side only is directional information, and the two
    # directions are different facts -- a sign on the observed side but not the declared means
    # an authority spoke during the run about an edge nobody had signed at configuration time;
    # the reverse is the odder of the two, and a consumer sees each alone, never summed.
    test "the two one-sided sign counts are directional, count :ungoverned as a sign, and count nothing that is changed-sign or unsigned on both sides" do
      pair = fn d, o ->
        declared = graph([srv(), tool("s"), tool("a")], [edge("s", "a", :declared, sign: d)])
        observed = graph([srv(), tool("s"), tool("a")], [edge("s", "a", :observed, sign: o)])
        {:ok, diff} = Diff.run(declared, observed, window: @window)
        {diff.coverage.declared_sign_only, diff.coverage.observed_sign_only}
      end

      assert pair.(:allow, :unset) == {1, 0}
      assert pair.(:unset, :deny) == {0, 1}
      assert pair.(:ungoverned, :unset) == {1, 0}
      assert pair.(:unset, :ungoverned) == {0, 1}
      assert pair.(:unset, :unset) == {0, 0}
      assert pair.(:allow, :deny) == {0, 0}
      assert pair.(:allow, :allow) == {0, 0}

      # Over every pair: one-sided exactly when one side is :unset and the other is not, and
      # never both counts at once.
      for d <- @signs, o <- @signs do
        {dso, oso} = pair.(d, o)

        assert dso == if(d != :unset and o == :unset, do: 1, else: 0),
               "declared #{d}, observed #{o}"

        assert oso == if(o != :unset and d == :unset, do: 1, else: 0),
               "declared #{d}, observed #{o}"
      end
    end

    test "a label on one side only is not a one-sided sign: the counts read labels in both graphs" do
      declared =
        graph([srv(), tool("s"), tool("a"), tool("b")], [edge("s", "a", :declared, sign: :allow)])

      observed =
        graph([srv(), tool("s"), tool("a"), tool("b")], [edge("s", "b", :observed, sign: :deny)])

      {:ok, diff} = Diff.run(declared, observed, window: @window)
      assert {diff.coverage.declared_sign_only, diff.coverage.observed_sign_only} == {0, 0}
    end

    test "completeness keeps the connectomics roles: what ran is the population, the declaration is the condition" do
      # A review lane found the first transposition was the dual -- population and condition
      # swapped. Two pairs where the two figures differ, from its report:
      #   (k) declared a->b, a->c, b->c; observed a->b, c->b: endpoint coverage 3/3 while
      #       only 1 of 3 declared edges ran; completeness 2/2 -- c->b ran between declared
      #       parts though nobody declared it, exactly the source's semantics.
      #   (d) declared holds a and nothing else; observed x->y: completeness 0/1 -- the run
      #       happened wholly outside the declared parts; no other figure tells that apart
      #       from an undeclared edge between declared parts (both are drift, both lower
      #       "observed edges declared" the same).
      nodes = [srv(), tool(:a), tool(:b), tool(:c)]

      declared =
        graph(nodes, [edge(:a, :b, :declared), edge(:a, :c, :declared), edge(:b, :c, :declared)])

      observed = graph(nodes, [edge(:a, :b, :observed), edge(:c, :b, :observed)])
      {:ok, k} = Diff.run(declared, observed, window: @window)
      assert k.coverage.declared_and_observed == 1
      assert k.coverage.declared_endpoint_covered == 3
      assert k.coverage.observed_endpoint_declared == 2

      #   and a -> x observed with a declared, x not: one end in the declaration is not
      #   between declared parts.
      declared = graph([srv(), tool(:a)], [])

      observed =
        graph([srv(), tool(:a), tool(:x), tool(:y)], [
          edge(:x, :y, :observed),
          edge(:a, :x, :observed)
        ])

      {:ok, d} = Diff.run(declared, observed, window: @window)
      assert d.coverage.observed_edges == 2
      assert d.coverage.observed_endpoint_declared == 0
      assert d.coverage.declared_endpoint_covered == 0
    end

    test "an endpoint the observed side never saw as a node lowers the completeness count and nothing else" do
      # Declared d -> e where the observed graph has neither node: the edge is dead authority
      # AND not endpoint-covered. Counts are integers; the fractions are the consumer's.
      {declared, observed} = crafted()

      # And a -> d: one endpoint observed (a), one not (d). Both ends must be observed for
      # the edge to count -- a mutant that took either was not killed until this edge.
      declared =
        graph(
          declared.nodes ++ [tool(:d), tool(:e)],
          declared.edges ++ [edge(:d, :e, :declared), edge(:a, :d, :declared)]
        )

      {:ok, diff} = Diff.run(declared, observed, window: @window)
      assert diff.coverage.declared_edges == 6
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
      # The non-raising forms answer the same bytes and hash.
      assert {:ok, Diff.encode!(a)} == Diff.encode(a)
      assert {:ok, Diff.hash!(a)} == Diff.hash(a)
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

      assert bytes =~ ~s("schema_version":3)
      assert bytes =~ ~s("observed_endpoint_declared":4,"observed_nodes":4)
      # The record's keys sort, so the algorithm is the first member a reader meets.
      assert String.starts_with?(bytes, ~s({"algorithm":"sha256","classes":{))

      assert bytes =~
               ~s("window":{"ended_at":"2026-09-14T01:00:00Z","started_at":"2026-09-14T00:00:00Z"})

      # No bare atom, no float, nothing but the record.
      refute bytes =~ ":invoke"
      refute bytes =~ "0."
    end

    test "the page's worked example is what the code writes: the bytes and the hash, read from the page" do
      # docs/connectome-diff.md carries the crafted pair's bytes in its one fenced block and
      # the hash on the line that follows; a reader reproduces them with sha256sum. This
      # test reads the page, so the page and the code cannot drift apart silently.
      page = File.read!("docs/connectome-diff.md")
      [_, block | _] = String.split(page, "\n```\n")
      [_, hex] = Regex.run(~r/SHA-256: `([0-9a-f]{64})`/, page)
      [_, hex384] = Regex.run(~r/SHA-384: `([0-9a-f]{96})`/, page)
      {declared, observed} = crafted()
      {:ok, diff} = Diff.run(declared, observed, window: @window)
      assert Diff.encode!(diff) == String.trim(block)
      assert Diff.hash_hex!(diff) == hex
      assert Diff.hash_hex!(diff, algorithm: :sha384) == hex384
      assert page =~ "The bytes (#{byte_size(String.trim(block))} of them, one line)"
    end

    test "a window with no canonical bytes is refused by name" do
      {declared, observed} = crafted()
      # The refusal names the window as the field, whatever shape was wrong.
      assert {:error, {:uncanonical, {:label_value, "record", :window, _}}} =
               Diff.run(declared, observed, window: %{ratio: 0.5})

      assert {:error, {:uncanonical, {:label_value, "record", :window, "1h"}}} =
               Diff.run(declared, observed, window: "1h")
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

  describe "changed-sign is two authorities disagreeing" do
    # The table, exhaustively: a label in both graphs is changed-sign when both signs are
    # supplied -- neither :unset -- and they differ. :unset is abstention, not a verdict, and
    # never participates; :ungoverned IS a supplied value, so it disagrees with :deny.

    test "of the twenty-five pairs, exactly the twelve with two supplied and different signs are changed-sign" do
      for d <- @signs, o <- @signs do
        declared =
          graph([srv(), tool("s"), tool("a")], [
            edge("s", "a", :declared, sign: d)
          ])

        observed =
          graph([srv(), tool("s"), tool("a")], [
            edge("s", "a", :observed, sign: o)
          ])

        {:ok, diff} = Diff.run(declared, observed, window: @window)
        expected = d != :unset and o != :unset and d != o

        assert diff.classes.changed_sign != [] == expected, "declared #{d}, observed #{o}"

        assert diff.classes.declared_and_observed != [] == not expected,
               "declared #{d}, observed #{o}"
      end
    end

    test ":ungoverned against :deny is changed-sign; :unset against :ungoverned is not" do
      declared =
        graph([srv(), tool("s"), tool("a")], [
          edge("s", "a", :declared, sign: :ungoverned)
        ])

      observed =
        graph([srv(), tool("s"), tool("a")], [
          edge("s", "a", :observed, sign: :deny)
        ])

      {:ok, diff} = Diff.run(declared, observed, window: @window)
      assert [%{declared_sign: :ungoverned, observed_sign: :deny}] = diff.classes.changed_sign

      declared =
        graph([srv(), tool("s"), tool("a")], [
          edge("s", "a", :declared, sign: :unset)
        ])

      observed =
        graph([srv(), tool("s"), tool("a")], [
          edge("s", "a", :observed, sign: :ungoverned)
        ])

      {:ok, diff} = Diff.run(declared, observed, window: @window)
      assert diff.classes.changed_sign == []
      assert length(diff.classes.declared_and_observed) == 1
    end

    test "the standalone case -- :unset on both sides -- never produces a finding" do
      declared =
        graph([srv(), tool("s"), tool("a")], [edge("s", "a", :declared)])

      observed =
        graph([srv(), tool("s"), tool("a")], [edge("s", "a", :observed)])

      {:ok, diff} = Diff.run(declared, observed, window: @window)
      assert diff.classes.changed_sign == [] and diff.classes.observed_but_undeclared == []
    end
  end

  describe "the sign is orthogonal to drift" do
    # :ungoverned means no gate applies, not "not declared"; if drift classification consulted
    # the sign, :ungoverned would become a way to hide drift.
    test "an observed edge nobody declared lands in observed_but_undeclared whatever the declared graph's signs" do
      declared =
        graph([srv(), tool("s"), tool("a"), tool("b")], [
          edge("s", "a", :declared, sign: :ungoverned)
        ])

      observed =
        graph([srv(), tool("s"), tool("a"), tool("b")], [
          edge("s", "a", :observed, sign: :ungoverned),
          edge("s", "b", :observed, sign: :ungoverned)
        ])

      {:ok, diff} = Diff.run(declared, observed, window: @window)
      assert [%{to: to}] = diff.classes.observed_but_undeclared
      assert to == id("b")
    end

    test "a declared :ungoverned edge is recorded exactly as any other: observed, it is declared_and_observed; never observed, it is dead authority" do
      declared =
        graph([srv(), tool("s"), tool("a"), tool("b")], [
          edge("s", "a", :declared, sign: :ungoverned),
          edge("s", "b", :declared, sign: :ungoverned)
        ])

      observed =
        graph([srv(), tool("s"), tool("a"), tool("b")], [
          edge("s", "a", :observed)
        ])

      {:ok, diff} = Diff.run(declared, observed, window: @window)
      assert [%{to: a}] = diff.classes.declared_and_observed
      assert a == id("a")
      assert [%{to: b}] = diff.classes.declared_never_observed
      assert b == id("b")
    end

    test "the record's schema_version is 3: its own axis, bumped when the algorithm joined the bytes" do
      declared =
        graph([srv(), tool("s"), tool("a")], [edge("s", "a", :declared)])

      observed =
        graph([srv(), tool("s"), tool("a")], [edge("s", "a", :observed)])

      {:ok, diff} = Diff.run(declared, observed, window: @window)
      assert diff.schema_version == 3
      assert Diff.to_record(diff).schema_version == 3
    end

    test "the record names its algorithm in the bytes, sha256 by default and sha384/sha512 by option, and the hash follows" do
      {declared, observed} = crafted()
      {:ok, diff} = Diff.run(declared, observed, window: @window)
      assert Diff.encode!(diff) == Diff.encode!(diff, algorithm: :sha256)
      bytes384 = Diff.encode!(diff, algorithm: :sha384)
      assert String.starts_with?(bytes384, ~s({"algorithm":"sha384","classes":{))
      assert Diff.hash!(diff, algorithm: :sha384) == :crypto.hash(:sha384, bytes384)

      assert Diff.hash_hex!(diff, algorithm: :sha512) ==
               Base.encode16(:crypto.hash(:sha512, Diff.encode!(diff, algorithm: :sha512)),
                 case: :lower
               )

      refute Map.has_key?(Diff.to_record(diff), :algorithm)
      assert_raise ArgumentError, ~r/algorithm/, fn -> Diff.encode(diff, algorithm: :md5) end
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

        # A label in both has both ends in both graphs, so each endpoint figure is a ceiling
        # on the shared count and never exceeds its own population.
        c = diff.coverage

        assert c.declared_and_observed <= c.declared_endpoint_covered and
                 c.declared_endpoint_covered <= c.declared_edges

        assert c.declared_and_observed <= c.observed_endpoint_declared and
                 c.observed_endpoint_declared <= c.observed_edges

        # With the node sets drawn per side, the endpoint counts are exact, not bounds: each
        # is the page's definition computed here from the two graphs' own ids. Before the
        # per-side draw both sides shared every node and the two counts could only ever
        # equal their own populations, so a mutant counting one endpoint as enough (Mdf4)
        # survived this property alone; it does not now.
        d_ids = MapSet.new(declared.nodes, & &1.id)
        o_ids = MapSet.new(observed.nodes, & &1.id)
        both = fn ids, e -> MapSet.member?(ids, e.from) and MapSet.member?(ids, e.to) end
        assert c.declared_endpoint_covered == Enum.count(declared.edges, &both.(o_ids, &1))
        assert c.observed_endpoint_declared == Enum.count(observed.edges, &both.(d_ids, &1))
        assert c.declared_nodes == MapSet.size(d_ids)
        assert c.observed_nodes == MapSet.size(o_ids)
        assert c.nodes_in_both == MapSet.size(MapSet.intersection(d_ids, o_ids))
      end
    end

    property "the diff is a function of the two graphs, not of the order their lists were built in" do
      check all({declared, observed} <- pair_gen()) do
        {:ok, a} = Diff.run(declared, observed, window: @window)
        # ExUnit seeds :rand for the test process from --seed, so the shuffle replays.
        shuffle = fn g -> graph(Enum.shuffle(g.nodes), Enum.shuffle(g.edges)) end

        {:ok, b} = Diff.run(shuffle.(declared), shuffle.(observed), window: @window)
        assert Diff.encode!(a) == Diff.encode!(b)
        assert Diff.hash!(a) == Diff.hash!(b)
        assert a == b
      end
    end
  end

  # A pair with its node set drawn PER SIDE, so a node can be declared and never observed
  # or observed and never declared, and the endpoint counts have something to count. Each
  # side keeps one fixed name so its edge generator never draws from an empty list, and the
  # two fixed names differ so neither side is a superset of the other by construction.
  defp pair_gen do
    gen all(
          # Two subsets of six names, drawn without a uniqueness generator (a six-term space
          # makes stream_data give up on uniqueness at small sizes).
          d_picks <- list_of(boolean(), length: 6),
          o_picks <- list_of(boolean(), length: 6),
          d_names = names([:a | picked(d_picks)]),
          o_names = names([:f | picked(o_picks)]),
          d_pairs <- pairs(d_names),
          o_pairs <- pairs(o_names)
        ) do
      build = fn pairs, prov ->
        pairs
        |> Enum.map(fn {a, b, k, s} -> edge(a, b, prov, kind: k, sign: s) end)
        |> Enum.uniq_by(&Edge.key/1)
      end

      {graph([srv() | Enum.map(d_names, &tool/1)], build.(d_pairs, :declared)),
       graph([srv() | Enum.map(o_names, &tool/1)], build.(o_pairs, :observed))}
    end
  end

  @names [:a, :b, :c, :d, :e, :f]
  defp picked(picks), do: for({n, true} <- Enum.zip(@names, picks), do: n)
  defp names(list), do: Enum.uniq(list)

  defp pairs(names) do
    list_of(
      {member_of(names), member_of(names), member_of([:invoke, :read, :message]),
       member_of([:allow, :deny, :hold, :ungoverned, :unset])},
      max_length: 8
    )
  end
end
