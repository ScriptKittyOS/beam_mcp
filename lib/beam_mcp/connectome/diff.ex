# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Connectome.Diff do
  @moduledoc """
  The declared connectome against the observed one: every edge of either in exactly one of
  four classes, and a coverage bound, as a record with canonical bytes a consumer can hash
  and sign.

  ## Labels, not isomorphism

  Two edges are the same edge iff their **label** -- `from`, `to`, `kind` -- is equal,
  compared as the encoder writes them: after NFC (rule 6 of `docs/connectome-canonical.md`).
  A graph whose ids coincide after NFC has no canonical bytes and so no diff -- refused by
  name, as `Canonical.encode/1` refuses it -- and a graph carrying the other side's
  provenance is refused too, so on every admitted input an edge and a label are the same
  count (a consumer lane found both: it normalised before comparing, as the rule says, and
  the code did not). Ids
  are structural (`BeamMCP.Connectome.Node.id/1`, one implementation site), so the label is
  the identity, and provenance says only which side an edge came from. This is a set
  difference over labels, and nothing more, on purpose: a graph-isomorphism check is NP-hard
  in general and would be *wrong* here besides -- it would call two differently named tools
  "the same" whenever their neighbourhoods matched. Nobody improves this into an isomorphism
  check; this paragraph is why.

  ## The four classes

    * `declared_and_observed` -- the label is in both graphs, and the signs are not both
      supplied and different;
    * `declared_never_observed` -- **dead authority**: declared, never seen in the window;
    * `observed_but_undeclared` -- **drift, a finding**: seen in the window, never declared;
    * `changed_sign` -- in both, and the consumer supplied a sign on BOTH sides (neither is
      `:unknown`) and they differ. A sign on one side only is not a change; the package
      never guesses what the missing one would have been.

  Every label of either input lands in exactly one class (a property test says so).

  ## The coverage bound, as counts

  A float has no canonical bytes, so the bound is integers the consumer divides:
  `declared_edges`, `observed_edges`, `declared_and_observed` (labels in both -- the two
  "in both" classes together), `declared_endpoint_covered` (declared edges whose `from`
  and `to` are both observed node ids -- the connectomics completeness figure, "synapses
  between fully proofread cells", transposed), `declared_nodes`, `observed_nodes`,
  `nodes_in_both`. The three fractions `docs/connectome.md` names are ratios of these:
  declared edges observed = `declared_and_observed / declared_edges`; observed edges
  declared = `declared_and_observed / observed_edges`; completeness =
  `declared_endpoint_covered / declared_edges`. The **window** is the consumer's input,
  carried verbatim and never inferred; a diff without one is refused by name.

  ## The bytes

  `encode/1` is `BeamMCP.Connectome.Canonical.encode_value/1` over `to_record/1`: the
  label grammar of a node's `"labels"` object (rule 4 of `docs/connectome-canonical.md`),
  so a consumer's existing verifier parses the diff unchanged. Each label is an object
  `from`, `kind`, `to`; a changed-sign entry adds `declared_sign` and `observed_sign`; the
  lists are sorted by the canonical order of `from`, then `to`, then `kind`, so equal
  inputs give equal bytes whatever order the graphs were built in. Nothing else enters the
  record: no weight, no latency, no argument, no name the graphs do not already carry.
  """

  alias BeamMCP.Connectome.{Canonical, Edge, Graph}

  @schema_version 1

  @typedoc "An edge's identity in the diff: from, to, kind."
  @type label :: %{from: String.t(), to: String.t(), kind: Edge.kind()}

  @typedoc "The entry for a label whose two supplied signs differ: the label with both."
  @type changed :: %{
          from: String.t(),
          to: String.t(),
          kind: Edge.kind(),
          declared_sign: Edge.sign(),
          observed_sign: Edge.sign()
        }

  @type classes :: %{
          declared_and_observed: [label()],
          declared_never_observed: [label()],
          observed_but_undeclared: [label()],
          changed_sign: [changed()]
        }

  @type coverage :: %{
          declared_edges: non_neg_integer(),
          observed_edges: non_neg_integer(),
          declared_and_observed: non_neg_integer(),
          declared_endpoint_covered: non_neg_integer(),
          declared_nodes: non_neg_integer(),
          observed_nodes: non_neg_integer(),
          nodes_in_both: non_neg_integer()
        }

  @type t :: %__MODULE__{
          schema_version: pos_integer(),
          window: map(),
          classes: classes(),
          coverage: coverage()
        }

  defstruct schema_version: @schema_version, window: %{}, classes: %{}, coverage: %{}

  @doc """
  The diff of `declared` against `observed`. `opts` carries `window:` (required, a map in
  the label grammar). Refuses by name: a graph `Graph.check/1` refuses (`{:declared, reason}`
  or `{:observed, reason}`), a missing window (`{:missing, :window}`), a window with no
  canonical bytes (`{:uncanonical, reason}`).
  """
  @spec run(Graph.t(), Graph.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def run(%Graph{} = declared, %Graph{} = observed, opts) do
    with :ok <- keyword(opts),
         :ok <- checked(:declared, declared),
         :ok <- checked(:observed, observed),
         {:ok, window} <- window(opts) do
      d = labels(declared)
      o = labels(observed)
      in_both = Map.keys(d) |> Enum.filter(&Map.has_key?(o, &1))
      observed_ids = MapSet.new(observed.nodes, &nfc(&1.id))
      declared_ids = MapSet.new(declared.nodes, &nfc(&1.id))

      {changed, same} =
        Enum.split_with(in_both, fn label -> changed_sign?(d[label], o[label]) end)

      classes = %{
        declared_and_observed: same |> Enum.map(&label_map/1) |> sort_labels(),
        declared_never_observed:
          d
          |> Map.keys()
          |> Enum.reject(&Map.has_key?(o, &1))
          |> Enum.map(&label_map/1)
          |> sort_labels(),
        observed_but_undeclared:
          o
          |> Map.keys()
          |> Enum.reject(&Map.has_key?(d, &1))
          |> Enum.map(&label_map/1)
          |> sort_labels(),
        changed_sign:
          changed
          |> Enum.map(fn label ->
            label
            |> label_map()
            |> Map.put(:declared_sign, d[label])
            |> Map.put(:observed_sign, o[label])
          end)
          |> sort_labels()
      }

      coverage = %{
        declared_edges: map_size(d),
        observed_edges: map_size(o),
        declared_and_observed: length(in_both),
        declared_endpoint_covered:
          Enum.count(Map.keys(d), fn {from, to, _kind} ->
            MapSet.member?(observed_ids, from) and MapSet.member?(observed_ids, to)
          end),
        declared_nodes: MapSet.size(declared_ids),
        observed_nodes: MapSet.size(observed_ids),
        nodes_in_both: MapSet.size(MapSet.intersection(declared_ids, observed_ids))
      }

      {:ok,
       %__MODULE__{
         schema_version: @schema_version,
         window: window,
         classes: classes,
         coverage: coverage
       }}
    end
  end

  @doc "The record as a plain map, in the shape the bytes are written from."
  @spec to_record(t()) :: map()
  def to_record(%__MODULE__{} = diff) do
    %{
      schema_version: diff.schema_version,
      window: diff.window,
      classes: diff.classes,
      coverage: diff.coverage
    }
  end

  @doc "The canonical bytes of the record: `Canonical.encode_value/1` over `to_record/1`."
  @spec encode(t()) :: {:ok, binary()} | {:error, term()}
  def encode(%__MODULE__{} = diff), do: Canonical.encode_value(to_record(diff))

  @doc "`encode/1`, raising."
  @spec encode!(t()) :: binary()
  def encode!(%__MODULE__{} = diff), do: Canonical.encode_value!(to_record(diff))

  @doc "SHA-256 over the canonical bytes."
  @spec hash(t()) :: {:ok, <<_::256>>} | {:error, term()}
  def hash(%__MODULE__{} = diff), do: Canonical.hash_value(to_record(diff))

  @doc "`hash/1`, raising."
  @spec hash!(t()) :: <<_::256>>
  def hash!(%__MODULE__{} = diff), do: Canonical.hash_value!(to_record(diff))

  @doc "The hash as lowercase hexadecimal, the form the page writes it in."
  @spec hash_hex(t()) :: {:ok, String.t()} | {:error, term()}
  def hash_hex(%__MODULE__{} = diff) do
    with {:ok, hash} <- hash(diff), do: {:ok, Base.encode16(hash, case: :lower)}
  end

  @doc "`hash_hex/1`, raising."
  @spec hash_hex!(t()) :: String.t()
  def hash_hex!(%__MODULE__{} = diff), do: Base.encode16(hash!(diff), case: :lower)

  defp keyword(opts) do
    if Keyword.keyword?(opts), do: :ok, else: {:error, {:invalid, :opts, opts}}
  end

  # A literal graph is read against everything Graph.new/1 refuses, then against
  # everything the encoder refuses -- a graph with no canonical bytes has no diff -- then
  # for the other side's provenance, before it is compared.
  defp checked(side, graph) do
    with :ok <- named(side, Graph.check(graph)),
         :ok <- named(side, canonical(graph)),
         do: named(side, provenance(side, graph))
  end

  defp named(_side, :ok), do: :ok
  defp named(side, {:error, reason}), do: {:error, {side, reason}}

  # `Graph.check/1` has already passed, so what remains of `Canonical.check/1` is the
  # canonical form's own refusals, given under their own names.
  defp canonical(graph) do
    case Canonical.check(graph) do
      {:error, {:uncanonical, {:invalid_graph, reason}}} -> {:error, reason}
      other -> other
    end
  end

  defp provenance(side, %Graph{edges: edges}) do
    case Enum.find(edges, &(&1.provenance != side)) do
      nil -> :ok
      %Edge{provenance: other} -> {:error, {:invalid, :provenance, other}}
    end
  end

  # The window is the consumer's and must already have canonical bytes: it is checked here
  # so a diff is refused at run/2, not at encode/1.
  defp window(opts) do
    case Keyword.fetch(opts, :window) do
      {:ok, window} ->
        with {:ok, _} <- Canonical.encode_value(window, :window), do: {:ok, window}

      :error ->
        {:error, {:missing, :window}}
    end
  end

  # label => sign, the ids NFC as the encoder writes them. A graph holds one edge per key
  # and provenance is one per graph (checked), so one edge per label.
  defp labels(%Graph{edges: edges}) do
    Map.new(edges, fn %Edge{from: from, to: to, kind: kind, sign: sign} ->
      {{nfc(from), nfc(to), kind}, sign}
    end)
  end

  defp nfc(s), do: String.normalize(s, :nfc)

  # Both supplied and different. `:unknown` on either side is not a change.
  defp changed_sign?(declared, observed),
    do: declared != :unknown and observed != :unknown and declared != observed

  defp label_map({from, to, kind}), do: %{from: from, to: to, kind: kind}

  # The canonical order: UTF-16 code units on from, then to, then the kind's name -- the same
  # order the encoder gives object keys, so the list order is the bytes' order.
  defp sort_labels(labels) do
    Enum.sort_by(labels, &{utf16(&1.from), utf16(&1.to), utf16(Atom.to_string(&1.kind))})
  end

  defp utf16(s), do: :unicode.characters_to_binary(s, :utf8, {:utf16, :big})
end
