# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Connectome.Reach do
  @moduledoc """
  Control-reachability queries over a connectome graph. Skeleton: every query answers
  `{:error, :not_implemented}` so that the tests written first fail as assertions and not
  as a missing module.
  """

  alias BeamMCP.Connectome.Graph

  defmodule Path do
    @moduledoc "A witness path: the nodes in order and the input edges between them."
    defstruct nodes: [], edges: []
    @type t :: %__MODULE__{nodes: [String.t()], edges: [BeamMCP.Connectome.Edge.t()]}
  end

  @spec reachable?(Graph.t(), String.t(), String.t(), keyword()) ::
          {:ok, boolean()} | {:error, term()}
  def reachable?(%Graph{}, _from, _to, _opts \\ []), do: {:error, :not_implemented}

  @spec reachable_without(Graph.t(), String.t(), String.t(), [String.t()], keyword()) ::
          {:ok, false | Path.t()} | {:error, term()}
  def reachable_without(%Graph{}, _from, _to, _gates, _opts \\ []), do: {:error, :not_implemented}

  @spec dominates?(Graph.t(), String.t(), String.t(), keyword()) ::
          {:ok, boolean()} | {:error, term()}
  def dominates?(%Graph{}, _gate, _target, _opts \\ []), do: {:error, :not_implemented}

  @spec mandatory_pass(Graph.t(), String.t(), keyword()) :: {:ok, MapSet.t()} | {:error, term()}
  def mandatory_pass(%Graph{}, _target, _opts \\ []), do: {:error, :not_implemented}

  @spec all_paths(Graph.t(), String.t(), String.t(), keyword()) ::
          {:error, {:refused, :all_paths}}
  def all_paths(%Graph{}, _from, _to, _opts \\ []), do: {:error, :not_implemented}
end
