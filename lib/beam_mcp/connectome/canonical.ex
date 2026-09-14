# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Connectome.Canonical do
  @moduledoc """
  The canonical bytes of a connectome, their hash, and the exports. The byte layout is
  specified in full in `docs/connectome-canonical.md`, so that a verifier can be written in
  another language without importing this package; that document is the contract and this
  module is one implementation of it.

  ## What the bytes carry, and what they do not

  The **declared form** is what a consumer signs: the schema version, every node (id, kind,
  level, labels) and every edge (from, to, kind, provenance, sign). **Weights are not in
  it** -- a weight is a measurement, and the declared hash is a claim about wiring -- and
  nothing that could print differently on two runtimes is in it either: a float, a
  reference, a pid or a tuple as a label value is refused by name rather than encoded.
  Weights travel in a separate **sidecar** that is never hashed with the declared bytes.

  Every atom is written as a string under the name of its field. `"module"` under `"kind"`
  and `"module"` under `"level"` are told apart by the key alone; no serialized form emits a
  bare atom.

  This module writes its own JSON: the value domain is small (objects, arrays, strings,
  integers, booleans, null) and the layout has to be reproducible in a few lines elsewhere.
  Nested objects sort their keys as RFC 8785 does, by UTF-16 code unit; the top level is the
  one deliberate departure from that scheme -- `schema_version`, `nodes`, `edges`, in that
  order, so the version is the first thing a reader meets.

  Strings are NFC-normalised before anything else. Two nodes whose ids coincide after
  normalisation are refused, never merged: the graph said they were two.
  """

  alias BeamMCP.Connectome.{Edge, Graph}

  @typedoc """
  Why a graph could not be encoded canonically. The first fault met is named; labels are
  read in term order (atoms before strings, strings bytewise), so which of two faults is
  named does not depend on the map's own order. Term order does not tell an integer key
  from the float equal to it; both are refused, and which is named first may vary.
  """
  @type uncanonical ::
          {:duplicate_id_after_nfc, String.t()}
          | {:label_value, String.t(), term(), term()}
          | {:label_key, String.t(), term()}
          | {:duplicate_label_key, String.t(), String.t()}
          | {:invalid_utf8, String.t(), term()}
          | {:invalid_graph, term()}
          | {:not_xml, String.t(), char()}

  @doc """
  The canonical bytes of the declared form of `graph`.
  """
  @spec encode(Graph.t()) :: {:ok, binary()} | {:error, {:uncanonical, uncanonical()}}
  def encode(%Graph{} = graph) do
    with :ok <- checked(graph),
         {:ok, nodes} <- canonical_nodes(graph.nodes),
         {:ok, edges} <- canonical_edges(graph.edges) do
      {:ok,
       IO.iodata_to_binary([
         ~s({"schema_version":),
         Integer.to_string(graph.schema_version),
         ~s(,"nodes":),
         array(nodes),
         ~s(,"edges":),
         array(edges),
         ?}
       ])}
    end
  end

  @doc "`encode/1`, raising `ArgumentError` with the same named reason."
  @spec encode!(Graph.t()) :: binary()
  def encode!(graph), do: bang(encode(graph), "encode")

  @doc """
  Everything `encode/1` refuses, without writing a byte: `Graph.check/1`'s refusals as
  `{:uncanonical, {:invalid_graph, reason}}`, then the canonical form's own -- two ids or
  two label keys that coincide after NFC, a string that is not UTF-8, a label value with no
  byte form. A graph this answers `:ok` for has canonical bytes; one it refuses has none.
  """
  @spec check(Graph.t()) :: :ok | {:error, {:uncanonical, uncanonical()}}
  def check(%Graph{} = graph) do
    with :ok <- checked(graph),
         {:ok, _nodes} <- canonical_nodes(graph.nodes),
         {:ok, _edges} <- canonical_edges(graph.edges) do
      :ok
    end
  end

  @doc """
  The canonical bytes of a value in the label grammar: the rules of a node's `"labels"`
  object (rule 4 of `docs/connectome-canonical.md`), applied to a map on its own.

  A record the package writes beside a graph -- the diff engine's, for one -- is encoded
  here rather than by a second layout: keys in UTF-16 order and unique after NFC, strings
  NFC, atoms as strings under their field names, integers, booleans, `null`, lists, nested
  maps; nothing else, refused by name. A consumer's verifier for a labels object reads it
  unchanged. A refusal names the value as a labels object would, with `"record"` in the
  id position and `field` -- `:record` unless the caller names one -- in the key position.
  """
  @spec encode_value(map(), atom()) :: {:ok, binary()} | {:error, {:uncanonical, uncanonical()}}
  def encode_value(value, field \\ :record)

  def encode_value(value, field) when is_map(value) and not is_struct(value) do
    with {:ok, object} <- value(value, "record", field), do: {:ok, json(object)}
  end

  def encode_value(value, field),
    do: {:error, {:uncanonical, {:label_value, "record", field, value}}}

  @doc "`encode_value/1`, raising."
  @spec encode_value!(map()) :: binary()
  def encode_value!(value), do: bang(encode_value(value), "encode_value")

  @doc "SHA-256 over `encode_value/1`'s bytes."
  @spec hash_value(map()) :: {:ok, <<_::256>>} | {:error, {:uncanonical, uncanonical()}}
  def hash_value(value) do
    with {:ok, bytes} <- encode_value(value), do: {:ok, :crypto.hash(:sha256, bytes)}
  end

  @doc "`hash_value/1`, raising."
  @spec hash_value!(map()) :: <<_::256>>
  def hash_value!(value), do: bang(hash_value(value), "hash_value")

  @doc "SHA-256 over the canonical bytes."
  @spec hash(Graph.t()) :: {:ok, <<_::256>>} | {:error, {:uncanonical, uncanonical()}}
  def hash(graph) do
    with {:ok, bytes} <- encode(graph), do: {:ok, :crypto.hash(:sha256, bytes)}
  end

  @doc "`hash/1`, raising."
  @spec hash!(Graph.t()) :: <<_::256>>
  def hash!(graph), do: bang(hash(graph), "hash")

  @doc "The hash as lowercase hexadecimal."
  @spec hash_hex(Graph.t()) :: {:ok, String.t()} | {:error, {:uncanonical, uncanonical()}}
  def hash_hex(graph) do
    with {:ok, h} <- hash(graph), do: {:ok, Base.encode16(h, case: :lower)}
  end

  @doc "`hash_hex/1`, raising."
  @spec hash_hex!(Graph.t()) :: String.t()
  def hash_hex!(graph), do: bang(hash_hex(graph), "hash_hex")

  @doc """
  The observed sidecar: the weights, keyed by edge, in the same layout rules. Never hashed
  with the declared bytes. Edges with no weight are omitted. A float weight is written in the
  shortest form that round-trips (this form is not part of any hash).
  """
  @spec sidecar(Graph.t()) :: {:ok, binary()} | {:error, {:uncanonical, uncanonical()}}
  def sidecar(%Graph{} = graph) do
    # Each edge is keyed on its own, never zipped against the sorted list: the canonical
    # order is the order of the normalised bytes, which the graph's order need not share.
    with :ok <- checked(graph),
         {:ok, _nodes} <- canonical_nodes(graph.nodes),
         {:ok, keyed} <-
           map_ok(graph.edges, &with({:ok, {key, _}} <- canonical_edge(&1), do: {:ok, {&1, key}})) do
      weights =
        keyed
        |> Enum.reject(fn {edge, _} -> is_nil(edge.weight) end)
        |> Enum.map(fn {edge, key} ->
          {key,
           object([
             {"from", elem(key, 0)},
             {"kind", elem(key, 2)},
             {"provenance", elem(key, 3)},
             {"to", elem(key, 1)},
             {"weight", weight(edge.weight)}
           ])}
        end)
        |> Enum.sort_by(&elem(&1, 0))
        |> Enum.map(&elem(&1, 1))

      {:ok,
       IO.iodata_to_binary([
         ~s({"schema_version":),
         Integer.to_string(graph.schema_version),
         ~s(,"weights":),
         array(weights),
         ?}
       ])}
    end
  end

  @doc "`sidecar/1`, raising."
  @spec sidecar!(Graph.t()) :: binary()
  def sidecar!(graph), do: bang(sidecar(graph), "sidecar")

  @doc "The JSON export: the canonical bytes themselves."
  @spec to_json(Graph.t()) :: {:ok, binary()} | {:error, {:uncanonical, uncanonical()}}
  def to_json(graph), do: encode(graph)

  @doc "`to_json/1`, raising."
  @spec to_json!(Graph.t()) :: binary()
  def to_json!(graph), do: bang(to_json(graph), "to_json")

  # ---------------------------------------------------------------------------------------
  # DOT and GraphML read the canonical order and never choose one of their own.

  @doc """
  The Graphviz DOT export. Node ids are quoted; kind, level and every label are attributes;
  edges carry kind, provenance and sign. Weights are not exported (they are not in the
  declared form).
  """
  @spec to_dot(Graph.t()) :: {:ok, binary()} | {:error, {:uncanonical, uncanonical()}}
  def to_dot(%Graph{} = graph) do
    with :ok <- checked(graph),
         {:ok, nodes} <- canonical_nodes(graph.nodes),
         {:ok, edges} <- canonical_edges(graph.edges) do
      node_lines =
        for {id, kind, level, labels} <- nodes do
          # The fixed names are DOT identifiers; a label's name carries the key, so it is
          # quoted as a value is -- a key may hold =, a space or a quote.
          attrs = [
            {"kind", kind},
            {"level", level}
            | Enum.map(labels, fn {k, v} -> {dot_q("label_" <> k), flat(v)} end)
          ]

          [
            "  ",
            dot_q(id),
            " [",
            Enum.map_join(attrs, ", ", fn {k, v} -> [k, ?=, dot_q(v)] end),
            "];\n"
          ]
        end

      edge_lines =
        for {{from, to, kind, prov}, sign} <- edges do
          [
            "  ",
            dot_q(from),
            " -> ",
            dot_q(to),
            " [kind=",
            dot_q(kind),
            ", provenance=",
            dot_q(prov),
            ", sign=",
            dot_q(sign),
            "];\n"
          ]
        end

      {:ok, IO.iodata_to_binary(["digraph connectome {\n", node_lines, edge_lines, "}\n"])}
    end
  end

  @doc "`to_dot/1`, raising."
  @spec to_dot!(Graph.t()) :: binary()
  def to_dot!(graph), do: bang(to_dot(graph), "to_dot")

  @doc """
  The GraphML export. Keys are declared once, as `l0`, `l1`, ... in canonical key order with
  `attr.name` carrying the label key (a GraphML key id is an NMTOKEN, which a label key need
  not be); nodes and edges follow the canonical order; text is XML-escaped (`&`, `<`, `>`,
  `"`, and tab, LF and CR as character references, which a parser preserves where it folds
  the literal characters). A character XML 1.0 cannot carry -- a C0 control other than tab, LF and CR, or a
  noncharacter such as U+FFFE -- is refused as `{:not_xml, id, codepoint}` rather than
  written: no character reference can carry it either, and every conforming parser would
  refuse the document. Weights are not exported.
  """
  @spec to_graphml(Graph.t()) :: {:ok, binary()} | {:error, {:uncanonical, uncanonical()}}
  def to_graphml(%Graph{} = graph) do
    with :ok <- checked(graph),
         {:ok, nodes} <- canonical_nodes(graph.nodes),
         {:ok, edges} <- canonical_edges(graph.edges),
         :ok <- xml_chars(nodes) do
      label_keys =
        nodes
        |> Enum.flat_map(fn {_, _, _, labels} -> Enum.map(labels, &elem(&1, 0)) end)
        |> Enum.uniq()
        |> Enum.sort(&utf16_be/2)

      key_id = label_keys |> Enum.with_index() |> Map.new(fn {k, i} -> {k, "l#{i}"} end)

      keys =
        [
          ~s(  <key id="kind" for="node" attr.name="kind" attr.type="string"/>\n),
          ~s(  <key id="level" for="node" attr.name="level" attr.type="string"/>\n)
        ] ++
          Enum.map(
            label_keys,
            &[
              ~s(  <key id="),
              key_id[&1],
              ~s(" for="node" attr.name="),
              xml(&1),
              ~s(" attr.type="string"/>\n)
            ]
          ) ++
          [
            ~s(  <key id="ekind" for="edge" attr.name="kind" attr.type="string"/>\n),
            ~s(  <key id="provenance" for="edge" attr.name="provenance" attr.type="string"/>\n),
            ~s(  <key id="sign" for="edge" attr.name="sign" attr.type="string"/>\n)
          ]

      node_xml =
        for {id, kind, level, labels} <- nodes do
          [
            ~s(    <node id="),
            xml(id),
            ~s(">\n),
            ~s(      <data key="kind">),
            xml(kind),
            "</data>\n",
            ~s(      <data key="level">),
            xml(level),
            "</data>\n"
          ] ++
            Enum.map(labels, fn {k, v} ->
              [~s(      <data key="), key_id[k], ~s(">), xml(flat(v)), "</data>\n"]
            end) ++ ["    </node>\n"]
        end

      edge_xml =
        for {{from, to, kind, prov}, sign} <- edges do
          [
            ~s(    <edge source="),
            xml(from),
            ~s(" target="),
            xml(to),
            ~s(">\n),
            ~s(      <data key="ekind">),
            xml(kind),
            "</data>\n",
            ~s(      <data key="provenance">),
            xml(prov),
            "</data>\n",
            ~s(      <data key="sign">),
            xml(sign),
            "</data>\n    </edge>\n"
          ]
        end

      {:ok,
       IO.iodata_to_binary([
         ~s(<?xml version="1.0" encoding="UTF-8"?>\n),
         ~s(<graphml xmlns="http://graphml.graphdrawing.org/xmlns">\n),
         keys,
         ~s(  <graph id="connectome" edgedefault="directed">\n),
         node_xml,
         edge_xml,
         "  </graph>\n</graphml>\n"
       ])}
    end
  end

  @doc "`to_graphml/1`, raising."
  @spec to_graphml!(Graph.t()) :: binary()
  def to_graphml!(graph), do: bang(to_graphml(graph), "to_graphml")

  # A host may build the graph struct by literal and bypass Graph.new/1; the encoder hashes
  # whatever it is given, so it reads the struct against everything new/1 refuses first,
  # under the graph's own name for the fault.
  defp checked(graph) do
    case Graph.check(graph) do
      :ok -> :ok
      {:error, reason} -> {:error, {:uncanonical, {:invalid_graph, reason}}}
    end
  end

  # ---------------------------------------------------------------------------------------
  # the canonical intermediate form: nodes as {id, kind, level, [{key, value}]} sorted by id;
  # edges as {{from, to, kind, provenance}, sign} sorted by key. Strings NFC, atoms named.

  defp canonical_nodes(nodes) do
    with {:ok, list} <- map_ok(nodes, &canonical_node/1) do
      sorted = Enum.sort_by(list, &elem(&1, 0))

      sorted
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.find(fn [a, b] -> elem(a, 0) == elem(b, 0) end)
      |> case do
        nil -> {:ok, sorted}
        [a, _] -> {:error, {:uncanonical, {:duplicate_id_after_nfc, elem(a, 0)}}}
      end
    end
  end

  defp canonical_node(node) do
    with {:ok, id} <- utf8(node.id, node.id, :id),
         id = nfc(id),
         {:ok, labels} <- labels(node.labels, id) do
      {:ok, {id, Atom.to_string(node.kind), Atom.to_string(node.level), labels}}
    end
  end

  # Pairs are read in term order, not the map's: past thirty-two keys a map lists its pairs
  # in hash order, and which of two faults is named would follow the runtime.
  defp labels(labels, id) do
    with {:ok, pairs} <- map_ok(Enum.sort(labels), fn {k, v} -> label(k, v, id) end) do
      unique_keys(pairs, id)
    end
  end

  # Two keys that coincide once normalised -- a combining sequence and its precomposed form,
  # or an atom and a string spelling one name -- would be written twice, and a reader in
  # another language collapses duplicates on parse and can never re-derive the bytes. Refused,
  # never merged, like ids.
  defp unique_keys(pairs, id) do
    sorted = Enum.sort_by(pairs, &elem(&1, 0), &utf16_be/2)

    sorted
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.find(fn [a, b] -> elem(a, 0) == elem(b, 0) end)
    |> case do
      nil -> {:ok, sorted}
      [a, _] -> {:error, {:uncanonical, {:duplicate_label_key, id, elem(a, 0)}}}
    end
  end

  defp label(k, v, id) do
    with {:ok, key} <- key(k, id),
         {:ok, value} <- value(v, id, k) do
      {:ok, {key, value}}
    end
  end

  defp key(k, _id) when is_atom(k) and not is_boolean(k) and not is_nil(k),
    do: {:ok, nfc(Atom.to_string(k))}

  defp key(k, id) when is_binary(k) do
    with {:ok, k} <- utf8(k, id, k), do: {:ok, nfc(k)}
  end

  defp key(k, id), do: {:error, {:uncanonical, {:label_key, id, k}}}

  # The value domain of the layout, and nothing else. A float prints differently across
  # runtimes; a reference, a pid, a tuple or a function has no byte form at all.
  defp value(v, id, k) when is_binary(v) do
    with {:ok, v} <- utf8(v, id, k), do: {:ok, nfc(v)}
  end

  defp value(v, _id, _k) when is_boolean(v) or is_nil(v), do: {:ok, v}
  defp value(v, _id, _k) when is_atom(v), do: {:ok, nfc(Atom.to_string(v))}
  defp value(v, _id, _k) when is_integer(v), do: {:ok, v}

  # A refusal inside a container names the label the container hangs from, and the whole
  # container, whatever depth it was met at; the inner key or element alone told a reader
  # nothing about where to look.
  defp value(v, id, k) when is_list(v) do
    case map_ok(v, &value(&1, id, k)) do
      {:ok, items} -> {:ok, {:array, items}}
      {:error, _} -> {:error, {:uncanonical, {:label_value, id, k, v}}}
    end
  end

  defp value(v, id, k) when is_map(v) and not is_struct(v) do
    with {:ok, pairs} <- map_ok(Enum.sort(v), fn {kk, vv} -> label(kk, vv, id) end),
         {:ok, sorted} <- unique_keys(pairs, id) do
      {:ok, {:object, sorted}}
    end
    |> case do
      {:ok, object} -> {:ok, object}
      {:error, _} -> {:error, {:uncanonical, {:label_value, id, k, v}}}
    end
  end

  defp value(v, id, k), do: {:error, {:uncanonical, {:label_value, id, k, v}}}

  defp canonical_edges(edges) do
    with {:ok, list} <- map_ok(edges, &canonical_edge/1) do
      {:ok, Enum.sort_by(list, &elem(&1, 0))}
    end
  end

  # An endpoint is a node id: Graph.new/1 refuses an edge whose endpoint names no node, and
  # both encode/1 and sidecar/1 read the nodes first, so a bad byte in an endpoint has
  # already been refused under the node's :id by the time an edge is keyed.
  defp canonical_edge(%Edge{} = e) do
    {:ok,
     {{nfc(e.from), nfc(e.to), Atom.to_string(e.kind), Atom.to_string(e.provenance)},
      Atom.to_string(e.sign)}}
  end

  # A binary that is not valid UTF-8 has no canonical bytes. A bitstring comprehension over
  # <<"a", 0xFF, "b">> stops at the bad byte and yields "a" (measured), so writing would emit
  # a prefix and two distinct strings could meet. Refused, naming the id and the field.
  defp utf8(s, id, field) do
    if String.valid?(s), do: {:ok, s}, else: {:error, {:uncanonical, {:invalid_utf8, id, field}}}
  end

  # ---------------------------------------------------------------------------------------
  # the JSON writer

  defp array(items) when is_list(items),
    do: [?[, Enum.map_join(items, ",", &json/1), ?]]

  defp object(pairs),
    do: [
      ?{,
      Enum.map_join(pairs, ",", fn {k, v} -> [json(k), ?:, json(v)] |> IO.iodata_to_binary() end),
      ?}
    ]

  defp json({id, kind, level, labels}) when is_binary(id) do
    IO.iodata_to_binary(
      object([{"id", id}, {"kind", kind}, {"labels", {:object, labels}}, {"level", level}])
    )
  end

  defp json({{from, to, kind, prov}, sign}) do
    IO.iodata_to_binary(
      object([{"from", from}, {"kind", kind}, {"provenance", prov}, {"sign", sign}, {"to", to}])
    )
  end

  defp json({:object, pairs}), do: IO.iodata_to_binary(object(pairs))
  defp json({:array, items}), do: IO.iodata_to_binary(array(items))
  defp json(iodata) when is_list(iodata), do: IO.iodata_to_binary(iodata)
  defp json(true), do: "true"
  defp json(false), do: "false"
  defp json(nil), do: "null"
  defp json(i) when is_integer(i), do: Integer.to_string(i)
  defp json(s) when is_binary(s), do: [?", escape(s), ?"] |> IO.iodata_to_binary()

  # RFC 8785 string escaping: the short forms, then \u00xx (lowercase) for the other
  # controls, everything else literal UTF-8.
  @short_escapes %{
    ?" => "\\\"",
    ?\\ => "\\\\",
    ?\b => "\\b",
    ?\t => "\\t",
    ?\n => "\\n",
    ?\f => "\\f",
    ?\r => "\\r"
  }

  defp escape(s) do
    for <<c::utf8 <- s>>, into: "", do: escape_char(c)
  end

  defp escape_char(c) when is_map_key(@short_escapes, c), do: @short_escapes[c]

  defp escape_char(c) when c < 0x20,
    do: "\\u" <> String.pad_leading(String.downcase(Integer.to_string(c, 16)), 4, "0")

  defp escape_char(c), do: <<c::utf8>>

  defp weight(w) when is_integer(w), do: w
  defp weight(w) when is_float(w), do: [:erlang.float_to_binary(w, [:short])]

  defp flat(v) when is_binary(v), do: v
  defp flat(v) when is_integer(v), do: Integer.to_string(v)
  defp flat(v) when is_boolean(v) or is_nil(v), do: json(v)
  defp flat({:object, _} = v), do: json(v)
  defp flat({:array, _} = v), do: json(v)

  defp dot_q(s),
    do: [
      ?",
      String.replace(s, ["\\", "\""], fn
        "\\" -> "\\\\"
        "\"" -> "\\\""
      end),
      ?"
    ]

  # Tab, LF and CR go as character references: a parser folds a literal one inside an
  # attribute value to a space, and a CR in content to LF (XML 1.0 3.3.3, 2.11), so ids that
  # differ only by whitespace kind would read back as one node. A reference survives both.
  @xml_escapes %{
    "&" => "&amp;",
    "<" => "&lt;",
    ">" => "&gt;",
    "\"" => "&quot;",
    "\t" => "&#9;",
    "\n" => "&#10;",
    "\r" => "&#13;"
  }

  defp xml(s), do: String.replace(s, Map.keys(@xml_escapes), &@xml_escapes[&1])

  # XML 1.0's Char production: #x9 | #xA | #xD | [#x20-#xD7FF] | [#xE000-#xFFFD] |
  # [#x10000-#x10FFFF]. Every string the export writes -- ids, keys, flattened values -- is
  # read against it first; the endpoints are ids already read.
  defp xml_chars(nodes) do
    Enum.find_value(nodes, :ok, fn {id, _kind, _level, labels} ->
      strings = [id | Enum.flat_map(labels, fn {k, v} -> [k, flat(v)] end)]

      case Enum.find_value(strings, &not_xml/1) do
        nil -> nil
        cp -> {:error, {:uncanonical, {:not_xml, id, cp}}}
      end
    end)
  end

  defp not_xml(s), do: Enum.find(String.to_charlist(s), &(not xml_char?(&1)))

  defp xml_char?(c) when c in [0x9, 0xA, 0xD], do: true
  defp xml_char?(c) when c >= 0x20 and c <= 0xD7FF, do: true
  defp xml_char?(c) when c >= 0xE000 and c <= 0xFFFD, do: true
  defp xml_char?(c) when c >= 0x10000 and c <= 0x10FFFF, do: true
  defp xml_char?(_), do: false

  # JCS orders object keys by UTF-16 code unit. A UTF-16BE binary compares byte-wise in
  # exactly that order, so the comparison is on the re-encoded key.
  defp utf16_be(a, b), do: utf16(a) <= utf16(b)
  defp utf16(s), do: :unicode.characters_to_binary(s, :utf8, {:utf16, :big})

  defp nfc(s), do: String.normalize(s, :nfc)

  defp map_ok(items, fun) do
    Enum.reduce_while(items, {:ok, []}, fn item, {:ok, acc} ->
      case fun.(item) do
        {:ok, v} -> {:cont, {:ok, [v | acc]}}
        {:error, _} = e -> {:halt, e}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      e -> e
    end
  end

  defp bang({:ok, v}, _), do: v
  defp bang({:error, reason}, what), do: raise(ArgumentError, "#{what}: #{inspect(reason)}")
end
