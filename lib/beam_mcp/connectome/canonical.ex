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

  @typedoc "Why a graph could not be encoded canonically."
  @type uncanonical ::
          {:duplicate_id_after_nfc, String.t()}
          | {:label_value, String.t(), term(), term()}
          | {:label_key, String.t(), term()}
          | {:duplicate_label_key, String.t(), String.t()}
          | {:invalid_utf8, String.t(), term()}

  @doc """
  The canonical bytes of the declared form of `graph`.
  """
  @spec encode(Graph.t()) :: {:ok, binary()} | {:error, {:uncanonical, uncanonical()}}
  def encode(%Graph{} = graph) do
    with {:ok, nodes} <- canonical_nodes(graph.nodes),
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
    with {:ok, _nodes} <- canonical_nodes(graph.nodes),
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
    with {:ok, nodes} <- canonical_nodes(graph.nodes),
         {:ok, edges} <- canonical_edges(graph.edges) do
      node_lines =
        for {id, kind, level, labels} <- nodes do
          attrs = [
            {"kind", kind},
            {"level", level} | Enum.map(labels, fn {k, v} -> {"label_" <> k, flat(v)} end)
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
  The GraphML export. Keys are declared once; nodes and edges follow the canonical order;
  text is XML-escaped (`&`, `<`, `>`, `"`). Weights are not exported.
  """
  @spec to_graphml(Graph.t()) :: {:ok, binary()} | {:error, {:uncanonical, uncanonical()}}
  def to_graphml(%Graph{} = graph) do
    with {:ok, nodes} <- canonical_nodes(graph.nodes),
         {:ok, edges} <- canonical_edges(graph.edges) do
      label_keys =
        nodes
        |> Enum.flat_map(fn {_, _, _, labels} -> Enum.map(labels, &elem(&1, 0)) end)
        |> Enum.uniq()
        |> Enum.sort(&utf16_le/2)

      keys =
        [
          ~s(  <key id="kind" for="node" attr.name="kind" attr.type="string"/>\n),
          ~s(  <key id="level" for="node" attr.name="level" attr.type="string"/>\n)
        ] ++
          Enum.map(
            label_keys,
            &[
              ~s(  <key id="label_),
              xml(&1),
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
              [~s(      <data key="label_), xml(k), ~s(">), xml(flat(v)), "</data>\n"]
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

  defp labels(labels, id) do
    with {:ok, pairs} <- map_ok(Map.to_list(labels), fn {k, v} -> label(k, v, id) end) do
      unique_keys(pairs, id)
    end
  end

  # Two keys that coincide once normalised -- a combining sequence and its precomposed form,
  # or an atom and a string spelling one name -- would be written twice, and a reader in
  # another language collapses duplicates on parse and can never re-derive the bytes. Refused,
  # never merged, like ids.
  defp unique_keys(pairs, id) do
    sorted = Enum.sort_by(pairs, &elem(&1, 0), &utf16_le/2)

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
    with {:ok, pairs} <- map_ok(Map.to_list(v), fn {kk, vv} -> label(kk, vv, id) end),
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
    do: [?[, Enum.map_join(items, ",", &json/1) |> to_string(), ?]]

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

  defp xml(s),
    do:
      s
      |> String.replace("&", "&amp;")
      |> String.replace("<", "&lt;")
      |> String.replace(">", "&gt;")
      |> String.replace("\"", "&quot;")

  # JCS orders object keys by UTF-16 code unit. A UTF-16BE binary compares byte-wise in
  # exactly that order, so the comparison is on the re-encoded key.
  defp utf16_le(a, b), do: utf16(a) <= utf16(b)
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
