# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Connectome.Graph do
  @moduledoc """
  A connectome: nodes, edges, and the version of the schema they follow. The vocabulary is in
  `docs/connectome.md`.

  A graph is held in canonical order -- nodes by id, edges by `Edge.key/1` -- so that two
  graphs built from the same parts in any order are equal, and a later slice can encode one
  to bytes without choosing an order of its own. `new/1` refuses a duplicate node id, a
  duplicate edge key, and an edge whose endpoint is not a node in the graph.

  `schema_version` is required and must be the one this module defines. A graph from a
  version this module does not know is refused rather than guessed at.
  """

  alias BeamMCP.Connectome.{Edge, Node}

  @schema_version 1
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
         {:ok, version} <- version(opts),
         {:ok, nodes} <- structs(opts, :nodes, Node),
         {:ok, edges} <- structs(opts, :edges, Edge),
         {:ok, nodes} <- unique(nodes, & &1.id, :duplicate_node),
         {:ok, edges} <- unique(edges, &Edge.key/1, :duplicate_edge),
         :ok <- endpoints_present(nodes, edges) do
      {:ok, %__MODULE__{schema_version: version, nodes: nodes, edges: edges}}
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

  defp version(opts) do
    case Keyword.fetch!(opts, :schema_version) do
      @schema_version -> {:ok, @schema_version}
      other -> {:error, {:invalid, :schema_version, other}}
    end
  end

  defp structs(opts, key, module) do
    value = Keyword.fetch!(opts, key)

    if is_list(value) and Enum.all?(value, &is_struct(&1, module)),
      do: {:ok, value},
      else: {:error, {:invalid, key, value}}
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
