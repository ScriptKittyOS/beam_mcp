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
            list_of(
              {member_of(names), member_of(names), member_of([:invoke, :read]),
               member_of([nil, 1, 7, 0.5])},
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
        |> Enum.map(fn {a, b, k, w} ->
          Edge.new!(
            from: Node.id({:tool, "srv", a}),
            to: Node.id({:tool, "srv", b}),
            kind: k,
            provenance: :declared,
            weight: w
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

      # And with every weight gone: the declared bytes never carried one.
      {:ok, c} =
        Graph.new(
          nodes: nodes,
          edges: Enum.map(edges, &%{&1 | weight: nil}),
          schema_version: @version
        )

      assert Canonical.encode!(a) == Canonical.encode!(c)
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

    test "a value with no byte form inside a list or a nested object is refused, naming the label and its whole value" do
      # Review found the refusal present at every depth but tested only at the top, and the
      # error for a nested object naming the inner key. The rule now: a refusal inside a
      # container names the label the container hangs from, and the container.
      bad = <<0xFF>>

      for v <- [
            [1, 0.5],
            %{"x" => 0.5},
            [[%{"y" => [2.0]}]],
            [self()],
            %{"t" => {1, 2}},
            [fn -> :never end],
            %{"m" => MapSet.new()},
            [bad],
            %{"cafe\u0301" => 1, "caf\u00e9" => 2}
          ] do
        n = Node.new!(kind: :tool, level: :server, identity: {:tool, "s", "x"}, labels: %{a: v})
        result = Canonical.encode(Graph.new!(nodes: [n], edges: [], schema_version: @version))
        id = n.id

        assert match?({:error, {:uncanonical, {:label_value, ^id, :a, ^v}}}, result),
               "not refused by label and whole value: #{inspect(v)} -> #{inspect(result)}"
      end
    end

    test "an atom label key or value is NFC-normalised like any other string" do
      # Atoms can carry non-ASCII names. A combining sequence in an atom and the precomposed
      # form in a string are the same key and the same value in the bytes.
      a =
        Node.new!(
          kind: :tool,
          level: :server,
          identity: {:tool, "s", "x"},
          labels: %{:"cafe\u0301" => :"cafe\u0301"}
        )

      b =
        Node.new!(
          kind: :tool,
          level: :server,
          identity: {:tool, "s", "x"},
          labels: %{"caf\u00e9" => "caf\u00e9"}
        )

      ga = Graph.new!(nodes: [a], edges: [], schema_version: @version)
      gb = Graph.new!(nodes: [b], edges: [], schema_version: @version)
      assert Canonical.encode!(ga) == Canonical.encode!(gb)
    end

    test "two label keys that coincide after NFC, or an atom and a string spelling one key, are refused, never emitted twice" do
      n =
        Node.new!(
          kind: :tool,
          level: :server,
          identity: {:tool, "s", "x"},
          labels: %{"cafe\u0301" => 1, "caf\u00e9" => 2}
        )

      assert {:error, {:uncanonical, {:duplicate_label_key, id, "caf\u00e9"}}} =
               Canonical.encode(Graph.new!(nodes: [n], edges: [], schema_version: @version))

      assert id == n.id

      n2 =
        Node.new!(
          kind: :tool,
          level: :server,
          identity: {:tool, "s", "x"},
          labels: %{"mode" => "b", mode: "a"}
        )

      assert {:error, {:uncanonical, {:duplicate_label_key, _, "mode"}}} =
               Canonical.encode(Graph.new!(nodes: [n2], edges: [], schema_version: @version))

      n3 =
        Node.new!(
          kind: :tool,
          level: :server,
          identity: {:tool, "s", "x"},
          labels: %{outer: %{"k" => 1, k: 2}}
        )

      assert {:error, {:uncanonical, {:label_value, _, :outer, _}}} =
               Canonical.encode(Graph.new!(nodes: [n3], edges: [], schema_version: @version))
    end

    test "well-formed UTF-8 is Unicode's: overlong forms, encoded surrogates and code points past U+10FFFF are refused; noncharacters and a BOM are written" do
      for bad <- [
            <<0xC0, 0x80>>,
            <<0xE0, 0x80, 0x80>>,
            <<0xED, 0xA0, 0x80>>,
            <<0xF4, 0x90, 0x80, 0x80>>,
            <<0x80>>,
            <<0xE2, 0x82>>
          ] do
        n = Node.new!(kind: :tool, level: :server, identity: {:tool, "s", "x"}, labels: %{t: bad})

        assert {:error, {:uncanonical, {:invalid_utf8, _, :t}}} =
                 Canonical.encode(Graph.new!(nodes: [n], edges: [], schema_version: @version)),
               "not refused: #{inspect(bad)}"
      end

      n =
        Node.new!(
          kind: :tool,
          level: :server,
          identity: {:tool, "s", "x"},
          labels: %{t: "\uFEFF\uFFFE\uFFFF"}
        )

      {:ok, bytes} = Canonical.encode(Graph.new!(nodes: [n], edges: [], schema_version: @version))
      assert bytes =~ "\"t\":\"\uFEFF\uFFFE\uFFFF\""
    end

    test "a singleton decomposition folds: U+212B and U+00C5 are one id" do
      a = Node.new!(kind: :tool, level: :server, identity: {:tool, "s", "\u212B"})
      b = Node.new!(kind: :tool, level: :server, identity: {:tool, "s", "\u00C5"})

      assert {:error, {:uncanonical, {:duplicate_id_after_nfc, "s/tool/\u00C5"}}} =
               Canonical.encode(Graph.new!(nodes: [a, b], edges: [], schema_version: @version))
    end

    test "when more than one label is refused, the one named does not depend on the map's internal order" do
      # A map past thirty-two keys lists its pairs in hash order, which is the runtime's;
      # this pair named "zz_bad" before the labels were read in term order.
      base = for i <- 1..100, into: %{}, do: {"k#{i}", i}
      labels = base |> Map.put("aa_bad", 0.5) |> Map.put("zz_bad", 0.5)
      n = Node.new!(kind: :tool, level: :server, identity: {:tool, "s", "x"}, labels: labels)

      assert {:error, {:uncanonical, {:label_value, _, "aa_bad", 0.5}}} =
               Canonical.encode(Graph.new!(nodes: [n], edges: [], schema_version: @version))
    end

    test "NFC, not NFKC: compatibility-equivalent strings stay two strings" do
      a = Node.new!(kind: :tool, level: :server, identity: {:tool, "s", "\uFB01"})
      b = Node.new!(kind: :tool, level: :server, identity: {:tool, "s", "fi"})

      {:ok, bytes} =
        Canonical.encode(Graph.new!(nodes: [a, b], edges: [], schema_version: @version))

      assert bytes =~ ~s("id":"s/tool/fi") and bytes =~ ~s("id":"s/tool/\uFB01")
    end

    test "nodes and edges sort by code point, label keys by UTF-16 code unit: the two orders differ above U+FFFF" do
      # U+1F600 is above U+FF01 by code point and below it by UTF-16 code unit (its lead
      # surrogate is 0xD83D). A verifier that sorts ids with a UTF-16 string comparison, as
      # JavaScript does by default, puts the nodes the other way round.
      fw = Node.new!(kind: :tool, level: :server, identity: {:tool, "s", "\uFF01"})
      sm = Node.new!(kind: :tool, level: :server, identity: {:tool, "s", "\u{1F600}"})
      e_fw = Edge.new!(from: fw.id, to: fw.id, kind: :invoke, provenance: :declared)
      e_sm = Edge.new!(from: sm.id, to: sm.id, kind: :invoke, provenance: :declared)

      {:ok, bytes} =
        Canonical.encode(
          Graph.new!(nodes: [sm, fw], edges: [e_sm, e_fw], schema_version: @version)
        )

      [_, nodes, edges] = String.split(bytes, ~r/"nodes":|"edges":/)
      assert nodes =~ ~r/s\/tool\/\x{FF01}.*s\/tool\/\x{1F600}/u
      assert edges =~ ~r/s\/tool\/\x{FF01}.*s\/tool\/\x{1F600}/u

      keyed =
        Node.new!(
          kind: :tool,
          level: :server,
          identity: {:tool, "s", "x"},
          labels: %{"\uFF01" => 1, "\u{1F600}" => 2}
        )

      {:ok, bytes} =
        Canonical.encode(Graph.new!(nodes: [keyed], edges: [], schema_version: @version))

      assert bytes =~ ~s("labels":{"\u{1F600}":2,"\uFF01":1})
    end

    test "a raw duplicate id and a duplicate after NFC are two refusals, under two names" do
      a = Node.new!(kind: :tool, level: :server, identity: {:tool, "s", "caf\u00e9"})
      b = Node.new!(kind: :tool, level: :server, identity: {:tool, "s", "cafe\u0301"})

      assert {:error, {:uncanonical, {:invalid_graph, {:duplicate_node, "s/tool/caf\u00e9"}}}} =
               Canonical.encode(%Graph{schema_version: @version, nodes: [a, a], edges: []})

      assert {:error, {:uncanonical, {:duplicate_id_after_nfc, "s/tool/caf\u00e9"}}} =
               Canonical.encode(Graph.new!(nodes: [a, b], edges: [], schema_version: @version))
    end

    test "edges sort by to before kind" do
      x = Node.new!(kind: :tool, level: :server, identity: {:tool, "s", "x"})
      a = Node.new!(kind: :tool, level: :server, identity: {:tool, "s", "a"})
      b = Node.new!(kind: :tool, level: :server, identity: {:tool, "s", "b"})
      ea = Edge.new!(from: x.id, to: a.id, kind: :read, provenance: :declared)
      eb = Edge.new!(from: x.id, to: b.id, kind: :invoke, provenance: :declared)

      {:ok, bytes} =
        Canonical.encode(Graph.new!(nodes: [x, a, b], edges: [eb, ea], schema_version: @version))

      [_, edges] = String.split(bytes, ~s("edges":))
      assert edges =~ ~r/"to":"s\/tool\/a"\}.*"to":"s\/tool\/b"\}/
    end

    test "a string that is not valid UTF-8 is refused by name, never truncated" do
      # A bitstring comprehension over an invalid byte stops silently: <<"a", 0xFF, "b">>
      # would have been written as "a", and two distinct ids could meet in the bytes.
      bad = <<"a", 0xFF, "b">>
      refute String.valid?(bad)

      %Node{} =
        n = Node.new!(kind: :tool, level: :server, identity: {:tool, "s", "x"}, labels: %{t: bad})

      assert {:error, {:uncanonical, {:invalid_utf8, id, :t}}} =
               Canonical.encode(Graph.new!(nodes: [n], edges: [], schema_version: @version))

      assert id == n.id

      # An id that is not valid UTF-8 cannot come from Node.id/1 with a string name, but a host
      # may build the struct by literal; Graph.new/1 admits any binary id.
      hand = %Node{n | id: bad, labels: %{}}

      assert {:error, {:uncanonical, {:invalid_utf8, ^bad, :id}}} =
               Canonical.encode(Graph.new!(nodes: [hand], edges: [], schema_version: @version))

      # The sidecar reads the nodes before it keys an edge, so an endpoint carrying the bad
      # bytes is refused as the node's id there too, never met as an endpoint.
      loop = Edge.new!(from: bad, to: bad, kind: :invoke, provenance: :declared, weight: 1)
      g = Graph.new!(nodes: [hand], edges: [loop], schema_version: @version)
      assert {:error, {:uncanonical, {:invalid_utf8, ^bad, :id}}} = Canonical.sidecar(g)
      assert {:error, {:uncanonical, {:invalid_utf8, ^bad, :id}}} = Canonical.encode(g)
    end

    test "escaping: quote, backslash and control characters; everything else literal UTF-8" do
      n =
        Node.new!(
          kind: :tool,
          level: :server,
          identity: {:tool, "s", "x"},
          labels: %{t: "a\"b\\c\n\t\b\f\r\u0001\u001f\u00e9/\u0000\u007f\u2028\u2029\u{1F600}"}
        )

      # DEL, U+2028, U+2029 and a character above U+FFFF are where other JSON writers
      # differ (a JavaScript-safe escaper writes \u2028; some write surrogate pairs); the
      # layout writes them literally, and NUL as \u0000.
      {:ok, bytes} = Canonical.encode(Graph.new!(nodes: [n], edges: [], schema_version: @version))

      assert bytes =~
               ~S("t":"a\"b\\c\n\t\b\f\r\u0001\u001fé/\u0000) <> "\u007f\u2028\u2029\u{1F600}\""
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

  test "the sidecar pairs each weight with the edge it belongs to, in the normalised order the graph did not hold" do
    # Raw order and canonical order differ here (the NFC case from the encoder test); a sidecar
    # built by zipping the graph's edge list with the canonical one attached each weight to the
    # wrong edge. Review found it; this pins it.
    a = Node.new!(kind: :tool, level: :server, identity: {:tool, "s", "cafe\u0301b"})
    b = Node.new!(kind: :tool, level: :server, identity: {:tool, "s", "caf\u00e9 a"})
    ea = Edge.new!(from: a.id, to: b.id, kind: :invoke, provenance: :observed, weight: 1)
    eb = Edge.new!(from: b.id, to: a.id, kind: :invoke, provenance: :observed, weight: 2)
    {:ok, g} = Graph.new(nodes: [a, b], edges: [ea, eb], schema_version: @version)
    decoded = Jason.decode!(Canonical.sidecar!(g))

    assert Enum.map(decoded["weights"], &{&1["from"], &1["weight"]}) ==
             [{"s/tool/caf\u00e9 a", 2}, {"s/tool/caf\u00e9b", 1}]
  end

  test "a literal-built graph is checked as Graph.new/1 would have, by every entry point" do
    # Review built %Graph{} by literal and reached the encoder unchecked: an edge from an
    # invalid-UTF-8 endpoint that named no node was written truncated and hashed; a struct
    # as labels was written with its __struct__. What Graph.new/1 refuses, the encoder
    # refuses too, under the graph's own name for it.
    bad = <<"a", 0xFF, "b">>
    %Node{} = n = Node.new!(kind: :tool, level: :server, identity: {:tool, "s", "x"})
    stray = Edge.new!(from: bad, to: n.id, kind: :invoke, provenance: :declared, weight: 1)
    literal = %Graph{schema_version: @version, nodes: [n], edges: [stray]}

    for f <- [
          &Canonical.encode/1,
          &Canonical.sidecar/1,
          &Canonical.to_dot/1,
          &Canonical.to_graphml/1
        ] do
      assert {:error, {:uncanonical, {:invalid_graph, {:dangling_edge, ^bad}}}} = f.(literal)
    end

    structy = %Graph{
      schema_version: @version,
      nodes: [%Node{n | labels: MapSet.new(["a"])}],
      edges: []
    }

    assert {:error, {:uncanonical, {:invalid_graph, {:invalid, :labels, %MapSet{}}}}} =
             Canonical.encode(structy)
  end

  test "the sidecar refuses what the declared form refuses: two ids that coincide after NFC" do
    # Review found sidecar/1 keying edges without reading the nodes, so a graph encode/1
    # refuses produced a sidecar with two entries under one key and no way to tell them apart.
    a = Node.new!(kind: :tool, level: :server, identity: {:tool, "s", "caf\u00e9"})
    b = Node.new!(kind: :tool, level: :server, identity: {:tool, "s", "cafe\u0301"})
    ea = Edge.new!(from: a.id, to: a.id, kind: :invoke, provenance: :observed, weight: 1)
    eb = Edge.new!(from: b.id, to: b.id, kind: :invoke, provenance: :observed, weight: 2)
    g = Graph.new!(nodes: [a, b], edges: [ea, eb], schema_version: @version)

    assert {:error, {:uncanonical, {:duplicate_id_after_nfc, "s/tool/caf\u00e9"}}} =
             Canonical.encode(g)

    assert {:error, {:uncanonical, {:duplicate_id_after_nfc, "s/tool/caf\u00e9"}}} =
             Canonical.sidecar(g)
  end

  test "the sidecar's float placement is the document's eleven examples, by digit count and not by magnitude" do
    a = Node.new!(kind: :tool, level: :server, identity: {:tool, "s", "a"})
    b = Node.new!(kind: :tool, level: :server, identity: {:tool, "s", "b"})

    for {w, text} <- [
          {0.1, "0.1"},
          {0.0001, "0.0001"},
          {999_999_999_999_999.0, "999999999999999.0"},
          {1.0e15, "1.0e15"},
          {1.0e-5, "1.0e-5"},
          {1.0e20, "1.0e20"},
          # Below 10^15 by magnitude and still written with an exponent: three digits.
          {9.99e14, "9.99e14"},
          {3.0e6, "3.0e6"},
          # Above 10^-4 by magnitude and still written with an exponent: six digits.
          {1.23456e-4, "1.23456e-4"},
          {0.001234, "0.001234"},
          {12340.0, "12340.0"}
        ] do
      e = Edge.new!(from: a.id, to: b.id, kind: :invoke, provenance: :observed, weight: w)
      g = Graph.new!(nodes: [a, b], edges: [e], schema_version: @version)

      assert Canonical.sidecar!(g) =~ ~s("weight":#{text}}),
             "#{inspect(w)} was not written as #{text}"
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

  describe "rule 8: the value domain, at its edges" do
    test "a negative integer, an integer beyond 2^53, an empty object and an empty array are written as the document says" do
      big = 9_007_199_254_740_993

      n =
        Node.new!(
          kind: :tool,
          level: :server,
          identity: {:tool, "s", "x"},
          labels: %{a: -1, b: big, c: %{}, d: []}
        )

      assert {:ok, bytes} =
               Canonical.encode(Graph.new!(nodes: [n], edges: [], schema_version: @version))

      assert bytes =~ ~s("labels":{"a":-1,"b":9007199254740993,"c":{},"d":[]})
    end

    test "nil, true and false are literals as values and refused as keys" do
      ok =
        Node.new!(
          kind: :tool,
          level: :server,
          identity: {:tool, "s", "x"},
          labels: %{a: nil, b: true, c: false}
        )

      assert {:ok, bytes} =
               Canonical.encode(Graph.new!(nodes: [ok], edges: [], schema_version: @version))

      assert bytes =~ ~s("labels":{"a":null,"b":true,"c":false})

      for k <- [nil, true, false] do
        n = Node.new!(kind: :tool, level: :server, identity: {:tool, "s", "x"}, labels: %{k => 1})

        assert {:error, {:uncanonical, {:label_key, _, ^k}}} =
                 Canonical.encode(Graph.new!(nodes: [n], edges: [], schema_version: @version))
      end
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
