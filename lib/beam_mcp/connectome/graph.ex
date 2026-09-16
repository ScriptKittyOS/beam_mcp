# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Connectome.Graph do
  @moduledoc """
  A connectome: nodes, edges, and the version of the schema they follow. The vocabulary is in
  `docs/connectome.md`.

  A graph is held in canonical order -- nodes by id, edges by `BeamMCP.Connectome.Edge.key/1` -- so that two
  graphs built from the same parts in any order are equal, and a later slice can encode one
  to bytes without choosing an order of its own. `new/1` refuses a duplicate node id, a
  duplicate edge key, and an edge whose endpoint is not a node in the graph.

  `schema_version` is required and must be the one this module defines. A graph from a
  version this module does not know is refused rather than guessed at.

  Every node and edge handed in is checked against its field domains --
  `BeamMCP.Connectome.Node.check/1`, `BeamMCP.Connectome.Edge.check/1` -- and refused by field, because a host may build a struct by literal and
  bypass the constructors, and a later slice hashes whatever this function accepted. Nothing
  is normalised, defaulted or rewritten: a sign a host wrote survives exactly as written when
  it is in the vocabulary, and is refused, not corrected, when it is not.
  """

  alias BeamMCP.Connectome.{Edge, Node}

  # 2 since 0.5.0: the sign vocabulary changed (`unknown` -> `unset`, `ungoverned` added), so
  # bytes at 1 and bytes at 2 read their signs against different vocabularies.
  @schema_version 3
  @keys [:nodes, :edges, :schema_version]
  @required [:nodes, :edges, :schema_version]

  @enforce_keys [:schema_version, :nodes, :edges]
  defstruct [:schema_version, nodes: [], edges: []]

  @type t :: %__MODULE__{
          schema_version: pos_integer(),
          nodes: [Node.t()],
          edges: [Edge.t()]
        }

  @doc "The schema version graphs built by this module carry."
  @spec schema_version() :: pos_integer()
  def schema_version, do: @schema_version

  @doc """
  Builds a graph from `nodes:`, `edges:` and `schema_version:`.

  Options are a keyword list; anything else is refused as `{:invalid, :opts, value}`.

  Refuses, by name: an unknown key (`{:unknown_key, key}`), a missing key (`{:missing, key}`),
  a schema version other than `schema_version/0` (`{:invalid, :schema_version, value}`), a
  `nodes:` or `edges:` value that is not a list of the structs (`{:invalid, :nodes, value}`,
  `{:invalid, :edges, value}`), a duplicate node id (`{:duplicate_node, id}`), a duplicate edge
  key (`{:duplicate_edge, key}`), and an edge endpoint that is not a node (`{:dangling_edge, id}`).
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, term()}
  def new(opts) do
    with :ok <- keyword(opts),
         :ok <- reject_unknown(opts),
         :ok <- require_keys(opts),
         {:ok, version, nodes, edges} <-
           validate(
             Keyword.fetch!(opts, :schema_version),
             Keyword.fetch!(opts, :nodes),
             Keyword.fetch!(opts, :edges)
           ) do
      {:ok, %__MODULE__{schema_version: version, nodes: nodes, edges: edges}}
    end
  end

  @doc """
  Reads a graph struct against everything `new/1` refuses, and corrects nothing.

  A host may build `%BeamMCP.Connectome.Graph{}` by literal and hand it to the encoder; the
  encoder hashes whatever it is given, so it asks this first. A graph `new/1` built passes.
  Order is not a fault: a literal graph in any order is the same graph, and the encoder
  sorts for itself. Refuses by the names `new/1` uses.
  """
  @spec check(t()) :: :ok | {:error, term()}
  def check(%__MODULE__{} = graph) do
    with {:ok, _version, _nodes, _edges} <-
           validate(graph.schema_version, graph.nodes, graph.edges),
         do: :ok
  end

  defp validate(version, nodes, edges) do
    with {:ok, version} <- version(version),
         {:ok, nodes} <- structs(:nodes, nodes, Node),
         {:ok, edges} <- structs(:edges, edges, Edge),
         :ok <- each(nodes, &Node.check/1),
         :ok <- each(edges, &Edge.check/1),
         {:ok, nodes} <- unique(nodes, & &1.id, :duplicate_node),
         {:ok, edges} <- unique(edges, &Edge.key/1, :duplicate_edge),
         :ok <- endpoints_present(nodes, edges) do
      {:ok, version, nodes, edges}
    end
  end

  @doc "`new/1`, raising `ArgumentError` with the same named reason."
  @spec new!(keyword()) :: t()
  def new!(opts) do
    case new(opts) do
      {:ok, graph} -> graph
      {:error, reason} -> raise ArgumentError, "invalid graph: #{inspect(reason)}"
    end
  end

  # Keyword options only. A map, nil, or a list that is not a keyword list is refused by name
  # rather than by a clause error, so new!/1 raises the ArgumentError its doc promises.
  defp keyword(opts) do
    if Keyword.keyword?(opts), do: :ok, else: {:error, {:invalid, :opts, opts}}
  end

  defp reject_unknown(opts) do
    case Enum.find(Keyword.keys(opts), &(&1 not in @keys)) do
      nil -> :ok
      key -> {:error, {:unknown_key, key}}
    end
  end

  defp require_keys(opts) do
    case Enum.find(@required, &(not Keyword.has_key?(opts, &1))) do
      nil -> :ok
      key -> {:error, {:missing, key}}
    end
  end

  defp version(@schema_version), do: {:ok, @schema_version}
  defp version(other), do: {:error, {:invalid, :schema_version, other}}

  defp structs(key, value, module) do
    if is_list(value) and Enum.all?(value, &is_struct(&1, module)),
      do: {:ok, value},
      else: {:error, {:invalid, key, value}}
  end

  # Every struct handed in is checked against its field domains and the first offender is
  # refused by field. A host may build a struct by literal and bypass the constructors; what
  # this function accepts is what a later slice hashes. Nothing is corrected.
  defp each(items, check) do
    Enum.find_value(items, :ok, fn item ->
      case check.(item) do
        :ok -> nil
        {:error, _} = error -> error
      end
    end)
  end

  # Sorted by the identity function, and refused on the first identity seen twice. The sort
  # is what makes the order canonical; the check is what makes the identity a key.
  defp unique(items, identity, error) do
    sorted = Enum.sort_by(items, identity)

    sorted
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.find(fn [a, b] -> identity.(a) == identity.(b) end)
    |> case do
      nil -> {:ok, sorted}
      [a, _] -> {:error, {error, identity.(a)}}
    end
  end

  defp endpoints_present(nodes, edges) do
    ids = MapSet.new(nodes, & &1.id)

    edges
    |> Enum.flat_map(&[&1.from, &1.to])
    |> Enum.find(&(not MapSet.member?(ids, &1)))
    |> case do
      nil -> :ok
      id -> {:error, {:dangling_edge, id}}
    end
  end
end
