# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Cursor do
  @moduledoc """
  The pagination codec every paginated list of this package shares.

  MCP paginates with an opaque cursor: a client passes back whatever `nextCursor` it was
  given and gets the results after it. This module is that cursor, once, for every list --
  the resource methods here, and the prompt methods when they arrive -- so that two lists
  never paginate two ways.

  ## Keyed on the item, not on an offset

  A cursor names a **position by key**: "after the item whose key is this". An offset says
  "skip this many", and a list that changes between two pages then skips an item that was
  there before and is there still, or shows one twice. A key does neither: the next page is
  every item whose key sorts after the cursor's, whatever was inserted or removed in between.
  The price is a canonical order, which every caller supplies by sorting on the key it names.

  ## Opaque, stable, typed

  The bytes are `Base.url_encode64/2` (no padding) over a small JSON object carrying a
  version, the list's kind and the key. Opaque by contract: a client passes it back
  unchanged and reads nothing from it. Stable: the same position is the same bytes. Typed:
  a cursor made for one list is refused by another, by name, so a `tools/list` cursor sent
  to `resources/list` is an invalid-params error and not a silently wrong page. Nothing is
  signed -- a forged cursor names a position, which any client may name by other means.
  """

  @version 1

  @typedoc "The list a cursor belongs to. One atom per paginated method."
  @type kind :: atom()

  @typedoc "The canonical key of an item -- the value the caller sorts on."
  @type key :: String.t()

  @typedoc "A decoded position: after this key. `nil` is the start of the list."
  @type position :: {:ok, key()} | nil

  @doc "Encodes the position after `key` on the list `kind`."
  @spec encode(kind(), key()) :: String.t()
  def encode(kind, key) when is_atom(kind) and is_binary(key) do
    %{"v" => @version, "k" => Atom.to_string(kind), "a" => key}
    |> Jason.encode!()
    |> Base.url_encode64(padding: false)
  end

  @doc """
  Decodes a cursor for the list `kind`.

  `{:error, :malformed}` for anything that is not this codec's bytes at this version with a
  string key; `{:error, {:kind, other}}` for a well-formed cursor made for another list,
  `other` being that list's name as the bytes carry it -- a string, never an atom made from
  the wire.
  """
  @spec decode(kind(), term()) :: {:ok, key()} | {:error, :malformed | {:kind, String.t()}}
  def decode(kind, cursor) when is_atom(kind) and is_binary(cursor) do
    with {:ok, json} <- Base.url_decode64(cursor, padding: false),
         {:ok, %{"v" => @version, "k" => k, "a" => key}} when is_binary(k) and is_binary(key) <-
           Jason.decode(json) do
      if k == Atom.to_string(kind), do: {:ok, key}, else: {:error, {:kind, k}}
    else
      _ -> {:error, :malformed}
    end
  end

  def decode(_kind, _cursor), do: {:error, :malformed}

  @doc """
  One page of `items`, which are sorted ascending on `key_fun`, from `position`, for the
  list `kind`.

  Returns the page and the cursor to pass for the next one, or `nil` when nothing remains --
  so `nextCursor` is present exactly when there is more. The cursor is encoded under `kind`,
  which is why the caller names it: the page does not know which list it serves.
  """
  @spec page(kind(), [item], (item -> key()), position(), pos_integer()) ::
          {[item], String.t() | nil}
        when item: term()
  def page(kind, items, key_fun, position, size)
      when is_atom(kind) and is_list(items) and is_function(key_fun, 1) and is_integer(size) and
             size > 0 do
    {page, rest} = items |> after_position(key_fun, position) |> Enum.split(size)
    {page, next_cursor(kind, page, rest, key_fun)}
  end

  defp after_position(items, _key_fun, nil), do: items

  defp after_position(items, key_fun, {:ok, key}),
    do: Enum.drop_while(items, &(key_fun.(&1) <= key))

  defp next_cursor(_kind, _page, [], _key_fun), do: nil
  defp next_cursor(kind, page, _rest, key_fun), do: encode(kind, key_fun.(List.last(page)))
end
