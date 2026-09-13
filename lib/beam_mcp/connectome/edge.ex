# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Connectome.Edge do
  @moduledoc """
  An edge of the connectome: one thing that can talk to, or did talk to, another. The
  vocabulary is in `docs/connectome.md`.

  ## The sign slot

  An edge carries a `sign` so that a rendered graph can show a policy's verdict beside it.
  **This package writes `:unknown` into that slot and nothing else.** `new/1` does not accept
  `:sign` as a key; the struct's default is `:unknown`; there is no setter. A host that renders
  its own policy does so on its own copy of the graph, outside this package. A census test
  over `lib/` holds this: no code line writes or names any other sign.

  ## Identity

  `key/1` -- from, to, kind, provenance -- is what makes two edges the same edge. Sign and
  weight are not part of it: they are what is said *about* the edge, not what it is. The key
  is an in-memory identity for sorting and de-duplication, not a wire shape: a serialized edge
  names every field, and never emits `kind` or `provenance` as a bare positional atom.
  """

  @kinds [:invoke, :read, :message, :supervise]
  @provenances [:declared, :observed]
  @signs [:allow, :deny, :hold, :unknown]
  @keys [:from, :to, :kind, :provenance, :weight]
  @required [:from, :to, :kind, :provenance]

  @enforce_keys [:from, :to, :kind, :provenance]
  defstruct [:from, :to, :kind, :provenance, :weight, sign: :unknown]

  @typedoc "What the edge is: a call, a read, a message, a supervision link."
  @type kind :: :invoke | :read | :message | :supervise

  @typedoc "Which build produced the edge."
  @type provenance :: :declared | :observed

  @typedoc "A policy's verdict on the edge; the package itself writes only `:unknown`."
  @type sign :: :allow | :deny | :hold | :unknown

  @typedoc "A measurement carried on the edge -- a count, a summary -- or nothing."
  @type weight :: nil | number()

  @typedoc "The identity of an edge."
  @type key :: {from :: String.t(), to :: String.t(), kind(), provenance()}

  @type t :: %__MODULE__{
          from: String.t(),
          to: String.t(),
          kind: kind(),
          provenance: provenance(),
          weight: weight(),
          sign: sign()
        }

  @doc """
  Builds an edge from `from:`, `to:` (node ids), `kind:`, `provenance:` and an optional
  `weight:`. Its sign is `:unknown`.

  Options are a keyword list; anything else is refused as `{:invalid, :opts, value}`.

  Refuses, by name: an unknown key -- `:sign` among them -- (`{:unknown_key, key}`), a
  missing required key (`{:missing, key}`), an endpoint that is not a node id, a kind or
  provenance outside the vocabulary, and a weight that is not `nil` or a non-negative number
  (each `{:invalid, field, value}`).
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, term()}
  def new(opts) do
    with :ok <- keyword(opts),
         :ok <- reject_unknown(opts),
         :ok <- require_keys(opts),
         {:ok, from} <- node_id(opts, :from),
         {:ok, to} <- node_id(opts, :to),
         {:ok, kind} <- member(opts, :kind, @kinds),
         {:ok, provenance} <- member(opts, :provenance, @provenances),
         {:ok, weight} <- weight(opts) do
      {:ok, %__MODULE__{from: from, to: to, kind: kind, provenance: provenance, weight: weight}}
    end
  end

  @doc "`new/1`, raising `ArgumentError` with the same named reason."
  @spec new!(keyword()) :: t()
  def new!(opts) do
    case new(opts) do
      {:ok, edge} -> edge
      {:error, reason} -> raise ArgumentError, "invalid edge: #{inspect(reason)}"
    end
  end

  @doc """
  Checks every field of a built edge against its domain, refusing by name. Reads only:
  nothing is normalised, defaulted or rewritten, and the sign is checked for membership and
  nothing else. `Graph.new/1` runs this over every edge it is handed, because a host may
  build an edge by literal and bypass `new/1`.
  """
  @spec check(t()) :: :ok | {:error, {:invalid, atom(), term()}}
  def check(%__MODULE__{} = edge) do
    checks = [
      {:from, &is_binary/1},
      {:to, &is_binary/1},
      {:kind, &(&1 in @kinds)},
      {:provenance, &(&1 in @provenances)},
      {:weight, &(is_nil(&1) or (is_number(&1) and &1 >= 0))},
      {:sign, &(&1 in @signs)}
    ]

    Enum.find_value(checks, :ok, fn {field, ok?} ->
      value = Map.fetch!(edge, field)
      if ok?.(value), do: nil, else: {:error, {:invalid, field, value}}
    end)
  end

  @doc "The identity of the edge: from, to, kind, provenance."
  @spec key(t()) :: key()
  def key(%__MODULE__{from: from, to: to, kind: kind, provenance: provenance}),
    do: {from, to, kind, provenance}

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

  defp node_id(opts, key) do
    case Keyword.fetch!(opts, key) do
      id when is_binary(id) -> {:ok, id}
      other -> {:error, {:invalid, key, other}}
    end
  end

  defp member(opts, key, allowed) do
    value = Keyword.fetch!(opts, key)
    if value in allowed, do: {:ok, value}, else: {:error, {:invalid, key, value}}
  end

  defp weight(opts) do
    case Keyword.get(opts, :weight) do
      nil -> {:ok, nil}
      w when is_number(w) and w >= 0 -> {:ok, w}
      other -> {:error, {:invalid, :weight, other}}
    end
  end
end
