# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Connectome.Node do
  @moduledoc """
  A node of the connectome: one part of a composed MCP system. The vocabulary is in
  `docs/connectome.md`; this module carries it as a struct and nothing more.

  Every field is named. `kind` and `level` are separate fields with separate types, and a node
  never has one inferred from the other, because `:module` and `:server` are each a member of
  both families -- two terms that share an atom, told apart by the field that holds them.

  ## Identity

  A node's `id` is structural: it is derived from what the node *is*, never from a counter or
  an insertion order, so two builds of the same system produce the same ids and a diff can
  line them up. `id/1` is the one function that derives it, and the only place in the package
  that does -- a second scheme is how two graphs stop agreeing about what a node is. The
  server component is the identity the host supplies for its server; a tool, resource, prompt
  or process is named within it; a module is named by its module, or at the finest level by
  module, function and arity.
  """

  @kinds [:server, :tool, :resource, :prompt, :process, :module]
  @levels [:mfa, :module, :boundary, :server]
  @keys [:kind, :level, :identity, :labels]
  @required [:kind, :level, :identity]

  @enforce_keys [:id, :kind, :level]
  defstruct [:id, :kind, :level, labels: %{}]

  @typedoc "What kind of part the node is."
  @type kind :: :server | :tool | :resource | :prompt | :process | :module

  @typedoc "The granularity the node was built at; coarsest last."
  @type level :: :mfa | :module | :boundary | :server

  @typedoc """
  The structural identity an id is derived from. The first element is the node's kind; the
  second is the server identity the host supplies.
  """
  @type identity ::
          {:server, server :: String.t()}
          | {:tool | :resource | :prompt | :process, server :: String.t(),
             name :: atom() | String.t()}
          | {:module, server :: String.t(), module()}
          | {:module, server :: String.t(), {module(), atom(), arity()}}

  @type t :: %__MODULE__{
          id: String.t(),
          kind: kind(),
          level: level(),
          labels: %{optional(atom()) => term()}
        }

  @doc """
  Builds a node from `kind:`, `level:`, `identity:` and an optional `labels:` map.

  Options are a keyword list; anything else is refused as `{:invalid, :opts, value}`.

  Refuses, by name: an unknown key (`{:unknown_key, key}`), a missing required key
  (`{:missing, key}`), a kind or level outside the vocabulary (`{:invalid, :kind, value}`,
  `{:invalid, :level, value}`), an identity whose tag is not the kind or whose shape `id/1`
  does not name (`{:invalid, :identity, value}`), a module identity at a level other than the
  one its shape means, and labels that are not a map.
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, term()}
  def new(opts) do
    with :ok <- keyword(opts),
         :ok <- reject_unknown(opts),
         :ok <- require_keys(opts),
         {:ok, kind} <- member(opts, :kind, @kinds),
         {:ok, level} <- member(opts, :level, @levels),
         {:ok, labels} <- labels(opts),
         {:ok, id} <- identity(opts, kind, level) do
      {:ok, %__MODULE__{id: id, kind: kind, level: level, labels: labels}}
    end
  end

  @doc "`new/1`, raising `ArgumentError` with the same named reason."
  @spec new!(keyword()) :: t()
  def new!(opts) do
    case new(opts) do
      {:ok, node} -> node
      {:error, reason} -> raise ArgumentError, "invalid node: #{inspect(reason)}"
    end
  end

  @doc """
  The id of the node with this identity: a string, stable, and distinct for distinct
  identities. Components are joined by `/` with any `/` or `%` inside a component escaped (the
  `%` first, so an escape cannot be forged), so two identities join to one string only when
  their components are the same strings. That is the one deliberate many-to-one: a name given
  as an atom and the same name given as a string are the same node.

  Raises `ArgumentError` for an identity shape the vocabulary does not name, or a server
  component that is not a string.
  """
  @spec id(identity()) :: String.t()
  def id(identity) do
    identity |> id_parts() |> Enum.map_join("/", &escape/1)
  end

  defp id_parts({:server, server}) when is_binary(server), do: [server, "server"]

  defp id_parts({kind, server, name})
       when kind in [:tool, :resource, :prompt, :process] and is_binary(server) and
              (is_atom(name) or is_binary(name)),
       do: [server, Atom.to_string(kind), to_string(name)]

  defp id_parts({:module, server, {m, f, a}})
       when is_binary(server) and is_atom(m) and is_atom(f) and is_integer(a) and a >= 0,
       do: [server, "module", inspect(m), Atom.to_string(f), Integer.to_string(a)]

  defp id_parts({:module, server, m}) when is_binary(server) and is_atom(m),
    do: [server, "module", inspect(m)]

  defp id_parts({_kind, server} = identity) when not is_binary(server),
    do:
      raise(
        ArgumentError,
        "the server component of an identity must be a string: #{inspect(identity)}"
      )

  defp id_parts({_kind, server, _} = identity) when not is_binary(server),
    do:
      raise(
        ArgumentError,
        "the server component of an identity must be a string: #{inspect(identity)}"
      )

  defp id_parts(identity),
    do: raise(ArgumentError, "not an identity the vocabulary names: #{inspect(identity)}")

  defp escape(component) do
    component |> String.replace("%", "%25") |> String.replace("/", "%2F")
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

  defp member(opts, key, allowed) do
    value = Keyword.fetch!(opts, key)
    if value in allowed, do: {:ok, value}, else: {:error, {:invalid, key, value}}
  end

  defp labels(opts) do
    case Keyword.get(opts, :labels, %{}) do
      labels when is_map(labels) -> {:ok, labels}
      other -> {:error, {:invalid, :labels, other}}
    end
  end

  # The identity's tag must be the node's kind, its shape must be one `id/1` names, and a
  # module identity carries its own level: module-function-arity is the :mfa level and a bare
  # module is not. That is a check of consistency between two given fields, not an inference
  # of one from the other.
  defp identity(opts, kind, level) do
    identity = Keyword.fetch!(opts, :identity)

    with true <- is_tuple(identity) and tuple_size(identity) >= 2 and elem(identity, 0) == kind,
         true <- mfa_level_consistent?(identity, level) do
      {:ok, id(identity)}
    else
      false -> {:error, {:invalid, :identity, identity}}
    end
  rescue
    ArgumentError -> {:error, {:invalid, :identity, Keyword.fetch!(opts, :identity)}}
  end

  defp mfa_level_consistent?({:module, _, {_, _, _}}, level), do: level == :mfa
  defp mfa_level_consistent?({:module, _, _}, level), do: level != :mfa
  defp mfa_level_consistent?(_, _), do: true
end
