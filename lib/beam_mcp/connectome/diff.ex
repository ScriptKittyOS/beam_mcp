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
  Ids are structural (`BeamMCP.Connectome.Node.id/1`, one implementation site), so the
  label is the identity, and provenance says only which side an edge came from. This is a
  set difference over labels, and nothing more, on purpose: a graph-isomorphism check is
  NP-hard in general and would be *wrong* here besides -- it would call two differently
  named tools "the same" whenever their neighbourhoods matched. Nobody improves this into an
  isomorphism check; this paragraph is why.

  Two inputs are admitted only as the encoder would admit them. A graph whose ids coincide
  after NFC has no canonical bytes and so no diff -- refused by name, as `BeamMCP.Connectome.Canonical.encode/1`
  refuses it -- and a graph carrying the other side's provenance is refused too, so on every
  admitted input an edge and a label are the same count (a consumer lane found both: it
  normalised before comparing, as the rule says, and the code did not).

  ## The four classes

    * `declared_and_observed` -- the label is in both graphs, and the signs are not both
      supplied and different;
    * `declared_never_observed` -- **dead authority**: declared, never seen in the window;
    * `observed_but_undeclared` -- **drift, a finding**: seen in the window, never declared;
    * `changed_sign` -- in both, and the consumer supplied a sign on BOTH sides (neither is
      `:unset`) and they differ: two authorities disagree. `:unset` is abstention, not a
      verdict, and never participates; `:ungoverned` is a supplied value and does. A sign on
      one side only is not a change; the package never guesses what the missing one would
      have been.

  Every label of either input lands in exactly one class (a property test says so).

  ## The coverage bound, as counts

  A float has no canonical bytes, so the bound is integers the consumer divides:
  `declared_edges`, `observed_edges`, `declared_and_observed` (labels in both -- the two
  "in both" classes together), `declared_endpoint_covered` (declared edges whose `from`
  and `to` are both observed node ids), `observed_endpoint_declared` (observed edges whose
  `from` and `to` are both declared node ids), `declared_nodes`, `observed_nodes`,
  `nodes_in_both`, and two one-sided sign counts -- `declared_sign_only` (labels in
  both with a sign supplied on the declared side and `:unset` on the observed) and
  `observed_sign_only` (the reverse: an authority spoke during the run about an edge nobody
  had signed at configuration time), one per direction because the two directions are
  different facts, and counts rather than a class because a sign on one side only is not a
  change. The fractions are ratios of these: declared edges observed =
  `declared_and_observed / declared_edges`; observed edges declared =
  `declared_and_observed / observed_edges`; **completeness** =
  `observed_endpoint_declared / observed_edges` -- the connectomics figure, "synapses
  between fully proofread cells", with its roles kept: what ran is the population, and
  the declaration is the condition on both ends (a review lane found the first draft had
  swapped them). `declared_endpoint_covered / declared_edges` is **endpoint coverage**,
  the dual: how much of the declaration sits where the window reached at all -- a ceiling
  on declared-edges-observed, never below it. The **window** is the consumer's input,
  carried verbatim and never inferred; a diff without one is refused by name.

  ## The bytes

  `encode/2` is `BeamMCP.Connectome.Canonical.encode_value/1` over `to_record/1` with the
  algorithm's name added under `"algorithm"` -- the label grammar of a node's `"labels"`
  object (rule 4 of `docs/connectome-canonical.md`), so a consumer's existing verifier
  parses the diff unchanged, and the record names the digest it is hashed with as the
  graph's envelope does (`algorithm:` on `encode/2`, `hash/2` and `hash_hex/2`; `:sha256`
  unless the caller says `:sha384` or `:sha512`; the keys sort, so the algorithm is the
  first member a reader meets). Each label is an object
  `from`, `kind`, `to`; a changed-sign entry adds `declared_sign` and `observed_sign`; the
  lists are sorted by the canonical order of `from`, then `to`, then `kind`, so equal
  inputs give equal bytes whatever order the graphs were built in. Nothing else enters the
  record: no weight, no latency, no argument, no name the graphs do not already carry.
  """

  alias BeamMCP.Connectome.{Canonical, Edge, Graph}

  # The record's own axis, separate from the graph's. 2 since 0.5.0: changed-sign excludes
  # `:unset` by name and the vocabulary it compares is the graph's at 2. 3 since the release
  # after: the record names its algorithm in the bytes, as the graph's envelope does.
  @schema_version 3

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
          observed_endpoint_declared: non_neg_integer(),
          declared_nodes: non_neg_integer(),
          observed_nodes: non_neg_integer(),
          nodes_in_both: non_neg_integer(),
          declared_sign_only: non_neg_integer(),
          observed_sign_only: non_neg_integer()
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
  the label grammar) and nothing else.

  Refuses by name, in this order: options that are not a keyword list or carry a key this
  function does not take (`{:invalid, :opts, given_or_keys}`); the declared graph, then the
  observed, each as `{:declared | :observed, reason}` -- `reason` being what `BeamMCP.Connectome.Graph.new/1`
  refuses, then what `BeamMCP.Connectome.Canonical.encode/1` refuses (a graph with no canonical bytes has no
  diff: `{:uncanonical, {:duplicate_id_after_nfc, id}}` and the rest), then an edge of the
  other side's provenance (`{:invalid, :provenance, other}`); a missing window
  (`{:missing, :window}`); a window with no canonical bytes
  (`{:uncanonical, {:label_value, "record", :window, value}}`). The first refusal in that
  order is the one answered.
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
        observed_endpoint_declared:
          Enum.count(Map.keys(o), fn {from, to, _kind} ->
            MapSet.member?(declared_ids, from) and MapSet.member?(declared_ids, to)
          end),
        declared_nodes: MapSet.size(declared_ids),
        observed_nodes: MapSet.size(observed_ids),
        nodes_in_both: MapSet.size(MapSet.intersection(declared_ids, observed_ids)),
        # A sign on one side only is not a change: it is counted, per direction, so a
        # consumer sees each alone. :unset means no sign was supplied on that side.
        declared_sign_only: Enum.count(in_both, &(d[&1] != :unset and o[&1] == :unset)),
        observed_sign_only: Enum.count(in_both, &(o[&1] != :unset and d[&1] == :unset))
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

  @doc """
  The canonical bytes of the record, naming the digest `algorithm:` chooses:
  `BeamMCP.Connectome.Canonical.encode_value/1` over `to_record/1` plus `"algorithm"`.
  """
  @spec encode(t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def encode(%__MODULE__{} = diff, opts \\ []),
    do: Canonical.encode_value(with_algorithm(diff, opts))

  @doc "`encode/2`, raising."
  @spec encode!(t(), keyword()) :: binary()
  def encode!(%__MODULE__{} = diff, opts \\ []),
    do: Canonical.encode_value!(with_algorithm(diff, opts))

  @doc "The digest the bytes name, over them: 32, 48 or 64 bytes by the algorithm."
  @spec hash(t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def hash(%__MODULE__{} = diff, opts \\ []) do
    algorithm = Canonical.algorithm!(opts)
    Canonical.hash_value(with_algorithm(diff, algorithm: algorithm), algorithm: algorithm)
  end

  @doc "`hash/2`, raising."
  @spec hash!(t(), keyword()) :: binary()
  def hash!(%__MODULE__{} = diff, opts \\ []) do
    case hash(diff, opts) do
      {:ok, hash} -> hash
      {:error, reason} -> raise ArgumentError, "hash: #{inspect(reason)}"
    end
  end

  @doc "The hash as lowercase hexadecimal, the form the page writes it in."
  @spec hash_hex(t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def hash_hex(%__MODULE__{} = diff, opts \\ []) do
    with {:ok, hash} <- hash(diff, opts), do: {:ok, Base.encode16(hash, case: :lower)}
  end

  @doc "`hash_hex/2`, raising."
  @spec hash_hex!(t(), keyword()) :: String.t()
  def hash_hex!(%__MODULE__{} = diff, opts \\ []),
    do: Base.encode16(hash!(diff, opts), case: :lower)

  # The record with the algorithm's name in it: what the bytes are written from. The struct
  # itself does not carry it -- the digest is the caller's choice at the moment of encoding,
  # as it is for the graph, not a property of the diff.
  defp with_algorithm(diff, opts),
    do: Map.put(to_record(diff), :algorithm, Canonical.algorithm!(opts))

  @options [:window]

  # A keyword list carrying only the options run/3 takes: a typo is refused by name, as
  # `Server.new/1` refuses one, rather than read as "no window given".
  defp keyword(opts) do
    cond do
      not Keyword.keyword?(opts) -> {:error, {:invalid, :opts, opts}}
      (unknown = Keyword.keys(opts) -- @options) != [] -> {:error, {:invalid, :opts, unknown}}
      true -> :ok
    end
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

  # `Graph.check/1` has already passed, so what `Canonical.check/1` can still refuse is the
  # canonical form's own: ids or label keys coinciding after NFC, a string that is not
  # UTF-8, a label value with no byte form.
  defp canonical(graph), do: Canonical.check(graph)

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

  # Both supplied and different: two authorities disagree. `:unset` on either side is not a
  # change -- no sign was supplied to this package on that side, so there is nothing to
  # disagree with. `:ungoverned` is supplied, and disagrees with `:deny`.
  defp changed_sign?(declared, observed),
    do: declared != :unset and observed != :unset and declared != observed

  defp label_map({from, to, kind}), do: %{from: from, to: to, kind: kind}

  # The canonical order: UTF-16 code units on from, then to, then the kind's name -- the same
  # order the encoder gives object keys, so the list order is the bytes' order.
  defp sort_labels(labels) do
    Enum.sort_by(labels, &{utf16(&1.from), utf16(&1.to), utf16(Atom.to_string(&1.kind))})
  end

  defp utf16(s), do: :unicode.characters_to_binary(s, :utf8, {:utf16, :big})
end
