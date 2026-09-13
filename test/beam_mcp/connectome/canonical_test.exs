# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Connectome.CanonicalTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias BeamMCP.Connectome.{Canonical, Edge, Graph, Node}

  @version Graph.schema_version()
  @fixtures "test/fixtures/connectome"

  # --- generators ---------------------------------------------------------------------------

  defp name_gen, do: string([?a..?z, ?0..?9, ?é, ?/], min_length: 1, max_length: 8)

  defp graph_gen do
    gen all(
          names <- uniq_list_of(name_gen(), min_length: 1, max_length: 6),
          pairs <-
            list_of({member_of(names), member_of(names), member_of([:invoke, :read])},
              max_length: 8
            ),
          labelled <- member_of(names)
        ) do
      server = Node.new!(kind: :server, level: :server, identity: {:server, "srv"})

      tools =
        for n <- names do
          labels =
            if n == labelled,
              do: %{command_class: :observe, mode: :read_only, note: "caf\u00e9"},
              else: %{}

          Node.new!(kind: :tool, level: :server, identity: {:tool, "srv", n}, labels: labels)
        end

      edges =
        pairs
        |> Enum.map(fn {a, b, k} ->
          Edge.new!(
            from: Node.id({:tool, "srv", a}),
            to: Node.id({:tool, "srv", b}),
            kind: k,
            provenance: :declared
          )
        end)
        |> Enum.uniq_by(&Edge.key/1)

      {[server | tools], edges}
    end
  end

  defp golden_graph do
    srv = Node.new!(kind: :server, level: :server, identity: {:server, "srv"})

    echo =
      Node.new!(
        kind: :tool,
        level: :server,
        identity: {:tool, "srv", "\u00e9cho"},
        labels: %{
          "nested" => %{"n" => 2, "ok" => true},
          command_class: :observe,
          mode: :read_only,
          title: "cafe\u0301"
        }
      )

    res = Node.new!(kind: :resource, level: :server, identity: {:resource, "srv", "r://a"})
    mod = Node.new!(kind: :module, level: :module, identity: {:module, "srv", Enum})

    grp =
      Node.new!(
        kind: :module,
        level: :boundary,
        identity: {:boundary, "srv", :application, :beam_mcp}
      )

    edges = [
      Edge.new!(from: srv.id, to: echo.id, kind: :invoke, provenance: :declared),
      Edge.new!(from: echo.id, to: res.id, kind: :read, provenance: :observed, weight: 3),
      Edge.new!(from: echo.id, to: mod.id, kind: :invoke, provenance: :declared),
      Edge.new!(from: mod.id, to: grp.id, kind: :message, provenance: :observed, weight: 1)
    ]

    Graph.new!(nodes: [srv, echo, res, mod, grp], edges: edges, schema_version: @version)
  end

  # --- properties ---------------------------------------------------------------------------

  property "graphs equal up to ordering encode to identical bytes and hashes" do
    check all({nodes, edges} <- graph_gen()) do
      {:ok, a} = Graph.new(nodes: nodes, edges: edges, schema_version: @version)

      {:ok, b} =
        Graph.new(
          nodes: Enum.shuffle(nodes),
          edges: Enum.shuffle(edges),
          schema_version: @version
        )

      assert Canonical.encode!(a) == Canonical.encode!(b)
      assert Canonical.hash!(a) == Canonical.hash!(b)
    end
  end

  property "a single label change flips the hash" do
    check all({nodes, edges} <- graph_gen(), pick <- integer(0..100)) do
      {:ok, g} = Graph.new(nodes: nodes, edges: edges, schema_version: @version)
      i = rem(pick, length(nodes))
      node = Enum.at(nodes, i)
      changed = %{node | labels: Map.put(node.labels, :touched, "x")}

      {:ok, g2} =
        Graph.new(
          nodes: List.replace_at(nodes, i, changed),
          edges: edges,
          schema_version: @version
        )

      assert Canonical.hash!(g) != Canonical.hash!(g2)
    end
  end

  # --- the bytes ----------------------------------------------------------------------------

  describe "encode/1" do
    test "schema_version first, then nodes by id, then edges by key; every other object sorted by key" do
      {:ok, bytes} = Canonical.encode(golden_graph())
      assert String.starts_with?(bytes, ~s({"schema_version":1,"nodes":[{"id":"))
      assert bytes == File.read!(Path.join(@fixtures, "golden.json"))
    end

    test "the declared form carries no weight, and every edge carries its sign under its name" do
      {:ok, bytes} = Canonical.encode(golden_graph())
      refute bytes =~ "weight"
      assert bytes =~ ~s("sign":"unknown")
      decoded = Jason.decode!(bytes)

      assert Enum.all?(
               decoded["edges"],
               &(Map.keys(&1) == ["from", "kind", "provenance", "sign", "to"])
             )

      assert Enum.all?(decoded["nodes"], &(Map.keys(&1) == ["id", "kind", "labels", "level"]))
    end

    test "no bare atom: every vocabulary word sits under the key of the family that owns it" do
      # :module is both a kind and a level. In the bytes it appears only as the value of
      # "kind" or of "level", so a reader tells the family by the key alone.
      decoded = Jason.decode!(Canonical.encode!(golden_graph()))

      words =
        ~w(server tool resource prompt process module mfa boundary invoke read message supervise allow deny hold unknown declared observed)

      for node <- decoded["nodes"], {key, value} <- node, is_binary(value), value in words do
        assert key in ["kind", "level"], "#{value} under #{key}"
      end

      for edge <- decoded["edges"], {key, value} <- edge, is_binary(value), value in words do
        assert key in ["kind", "sign", "provenance"], "#{value} under #{key}"
      end

      kinds = Enum.map(decoded["nodes"], & &1["kind"])
      levels = Enum.map(decoded["nodes"], & &1["level"])
      assert "module" in kinds and "module" in levels
    end

    test "strings are NFC-normalised: a combining sequence and its precomposed form encode identically" do
      a =
        Node.new!(
          kind: :tool,
          level: :server,
          identity: {:tool, "s", "x"},
          labels: %{t: "cafe\u0301"}
        )

      b =
        Node.new!(
          kind: :tool,
          level: :server,
          identity: {:tool, "s", "x"},
          labels: %{t: "caf\u00e9"}
        )

      ga = Graph.new!(nodes: [a], edges: [], schema_version: @version)
      gb = Graph.new!(nodes: [b], edges: [], schema_version: @version)
      assert Canonical.encode!(ga) == Canonical.encode!(gb)
      assert Canonical.encode!(ga) =~ "caf\u00e9"
    end

    test "the canonical order is the order of the NORMALISED bytes, which the graph's own order is not" do
      # Raw, "cafe" + combining acute + "b" sorts before "caf" + precomposed é + " a" (0x65 < 0xC3
      # at the fourth byte), so Graph.new/1 holds them in that order. After NFC both begin
      # "café" and the sixth bytes decide: " " (0x20) before "b" (0x62). The encoder must sort
      # by what it writes, not by what it was handed -- a mutant that skipped the sort kept the
      # graph's order and survived every test that built its graph through Graph.new/1.
      a = Node.new!(kind: :tool, level: :server, identity: {:tool, "s", "cafe\u0301b"})
      b = Node.new!(kind: :tool, level: :server, identity: {:tool, "s", "caf\u00e9 a"})
      assert a.id < b.id
      ea = Edge.new!(from: a.id, to: b.id, kind: :invoke, provenance: :declared)
      eb = Edge.new!(from: b.id, to: a.id, kind: :invoke, provenance: :declared)
      {:ok, g} = Graph.new(nodes: [a, b], edges: [ea, eb], schema_version: @version)
      assert Enum.map(g.nodes, & &1.id) == [a.id, b.id]

      decoded = Jason.decode!(Canonical.encode!(g))
      assert Enum.map(decoded["nodes"], & &1["id"]) == ["s/tool/caf\u00e9 a", "s/tool/caf\u00e9b"]

      assert Enum.map(decoded["edges"], & &1["from"]) == [
               "s/tool/caf\u00e9 a",
               "s/tool/caf\u00e9b"
             ]
    end

    test "two ids that coincide after NFC are refused, never merged" do
      a = Node.new!(kind: :tool, level: :server, identity: {:tool, "s", "cafe\u0301"})
      b = Node.new!(kind: :tool, level: :server, identity: {:tool, "s", "caf\u00e9"})
      assert a.id != b.id
      {:ok, g} = Graph.new(nodes: [a, b], edges: [], schema_version: @version)
      assert {:error, {:uncanonical, {:duplicate_id_after_nfc, _}}} = Canonical.encode(g)
    end

    test "a label value the layout cannot carry is refused by node, key and value" do
      n =
        Node.new!(kind: :tool, level: :server, identity: {:tool, "s", "x"}, labels: %{ratio: 0.5})

      g = Graph.new!(nodes: [n], edges: [], schema_version: @version)
      assert {:error, {:uncanonical, {:label_value, id, :ratio, 0.5}}} = Canonical.encode(g)
      assert id == n.id

      n2 =
        Node.new!(
          kind: :tool,
          level: :server,
          identity: {:tool, "s", "x"},
          labels: %{ref: make_ref()}
        )

      assert {:error, {:uncanonical, {:label_value, _, :ref, _}}} =
               Canonical.encode(Graph.new!(nodes: [n2], edges: [], schema_version: @version))
    end

    test "the whole label value domain: strings, atoms, integers, booleans, null, arrays and objects of them" do
      n =
        Node.new!(
          kind: :tool,
          level: :server,
          identity: {:tool, "s", "x"},
          labels: %{
            "list" => [1, "a", nil, false, %{"k" => :atom}],
            flag: true,
            none: nil,
            n: -3,
            zero: 0
          }
        )

      g = Graph.new!(nodes: [n], edges: [], schema_version: @version)
      {:ok, bytes} = Canonical.encode(g)

      assert bytes =~
               ~s("labels":{"flag":true,"list":[1,"a",null,false,{"k":"atom"}],"n":-3,"none":null,"zero":0})

      # The exporters flatten the same values, in the same order, and never a weight.
      dot = Canonical.to_dot!(g)

      assert dot =~
               ~S(label_flag="true", label_list="[1,\"a\",null,false,{\"k\":\"atom\"}]", label_n="-3")

      assert dot =~ ~S(label_none="null", label_zero="0")
      graphml = Canonical.to_graphml!(g)

      assert graphml =~
               ~s(<data key="label_list">[1,&quot;a&quot;,null,false,{&quot;k&quot;:&quot;atom&quot;}]</data>)

      refute graphml =~ "weight"
    end

    test "a label key that is not an atom or a string is refused by node and key; inside a nested value, by value" do
      n =
        Node.new!(
          kind: :tool,
          level: :server,
          identity: {:tool, "s", "x"},
          labels: %{7 => "seven"}
        )

      assert {:error, {:uncanonical, {:label_key, id, 7}}} =
               Canonical.encode(Graph.new!(nodes: [n], edges: [], schema_version: @version))

      assert id == n.id

      n2 =
        Node.new!(
          kind: :tool,
          level: :server,
          identity: {:tool, "s", "x"},
          labels: %{outer: %{8 => "eight"}}
        )

      assert {:error, {:uncanonical, {:label_value, _, :outer, %{8 => "eight"}}}} =
               Canonical.encode(Graph.new!(nodes: [n2], edges: [], schema_version: @version))
    end

    test "escaping: quote, backslash and control characters; everything else literal UTF-8" do
      n =
        Node.new!(
          kind: :tool,
          level: :server,
          identity: {:tool, "s", "x"},
          labels: %{t: "a\"b\\c\n\t\u0001\u001f\u00e9/"}
        )

      {:ok, bytes} = Canonical.encode(Graph.new!(nodes: [n], edges: [], schema_version: @version))
      assert bytes =~ ~S("t":"a\"b\\c\n\t\u0001\u001fé/")
    end

    test "label keys sort by UTF-16 code unit, the order the JSON canonicalization scheme uses" do
      # U+1F600 (surrogate pair, first unit 0xD83D) sorts BEFORE U+FF01 (0xFF01) in UTF-16 and
      # after it by code point. The layout says UTF-16, so the emoji key comes first.
      n =
        Node.new!(
          kind: :tool,
          level: :server,
          identity: {:tool, "s", "x"},
          labels: %{"\u{1F600}" => 1, "\uFF01" => 2}
        )

      {:ok, bytes} = Canonical.encode(Graph.new!(nodes: [n], edges: [], schema_version: @version))
      assert bytes =~ ~s("labels":{"\u{1F600}":1,"\uFF01":2})
    end
  end

  describe "hash/1 and the sidecar" do
    test "the hash is SHA-256 over the bytes, hex lowercase" do
      g = golden_graph()
      {:ok, bytes} = Canonical.encode(g)
      assert Canonical.hash!(g) == :crypto.hash(:sha256, bytes)
      assert Canonical.hash_hex!(g) == Base.encode16(:crypto.hash(:sha256, bytes), case: :lower)

      assert Canonical.hash_hex!(g) ==
               String.trim(File.read!(Path.join(@fixtures, "golden.sha256")))
    end

    test "a weight change alters the sidecar and not the hash" do
      g = golden_graph()
      [e | rest] = Enum.filter(g.edges, &(&1.weight != nil))
      heavier = %{e | weight: e.weight + 10}

      {:ok, g2} =
        Graph.new(
          nodes: g.nodes,
          edges: [heavier | rest] ++ Enum.filter(g.edges, &(&1.weight == nil)),
          schema_version: @version
        )

      assert Canonical.hash!(g) == Canonical.hash!(g2)
      assert Canonical.sidecar!(g) != Canonical.sidecar!(g2)
      assert Canonical.sidecar!(g) == File.read!(Path.join(@fixtures, "golden.sidecar.json"))
    end
  end

  test "a float weight is written in the sidecar in its shortest round-tripping form, and is in no hash" do
    a = Node.new!(kind: :tool, level: :server, identity: {:tool, "s", "a"})
    b = Node.new!(kind: :tool, level: :server, identity: {:tool, "s", "b"})
    e = Edge.new!(from: a.id, to: b.id, kind: :invoke, provenance: :observed, weight: 0.1)
    g = Graph.new!(nodes: [a, b], edges: [e], schema_version: @version)
    assert Canonical.sidecar!(g) =~ ~s("weight":0.1})
    refute Canonical.encode!(g) =~ "0.1"
  end

  test "the bang forms raise the named reason; DOT quotes a backslash in an id" do
    n =
      Node.new!(
        kind: :tool,
        level: :server,
        identity: {:tool, "s", "back\\slash"},
        labels: %{r: 0.5}
      )

    g = Graph.new!(nodes: [n], edges: [], schema_version: @version)

    assert_raise ArgumentError, ~r/encode: \{:uncanonical, \{:label_value/, fn ->
      Canonical.encode!(g)
    end

    ok = Graph.new!(nodes: [%{n | labels: %{}}], edges: [], schema_version: @version)
    assert Canonical.to_dot!(ok) =~ ~S("s/tool/back\\slash" [kind="tool")
  end

  describe "exporters" do
    test "DOT and GraphML are byte-exact against their goldens, and follow the canonical order" do
      g = golden_graph()
      assert Canonical.to_dot!(g) == File.read!(Path.join(@fixtures, "golden.dot"))
      assert Canonical.to_graphml!(g) == File.read!(Path.join(@fixtures, "golden.graphml"))
      assert Canonical.to_json!(g) == Canonical.encode!(g)
    end
  end

  describe "the worked example in docs/connectome-canonical.md" do
    test "the document's bytes and hex are what the encoder produces" do
      doc = File.read!("docs/connectome-canonical.md")
      [_, bytes_in_doc] = Regex.run(~r/```json-canonical\n(.*?)\n```/s, doc)
      [_, hex_in_doc] = Regex.run(~r/sha256: `([0-9a-f]{64})`/, doc)

      s = Node.new!(kind: :server, level: :server, identity: {:server, "s"})

      t =
        Node.new!(
          kind: :tool,
          level: :server,
          identity: {:tool, "s", "t"},
          labels: %{mode: :read_only}
        )

      e = Edge.new!(from: s.id, to: t.id, kind: :invoke, provenance: :declared)
      g = Graph.new!(nodes: [s, t], edges: [e], schema_version: @version)

      assert Canonical.encode!(g) == bytes_in_doc
      assert Canonical.hash_hex!(g) == hex_in_doc
    end
  end
end
