# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.CursorTest do
  @moduledoc """
  The pagination codec every paginated list of this package shares.

  A cursor is opaque to a client, stable for a position, typed by the list it belongs to, and
  keyed on the item's canonical key rather than an offset -- so a list that changes between
  two pages never skips an item that was there before and is there still. Written red before
  `BeamMCP.Cursor` existed.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias BeamMCP.Cursor

  describe "encode/2 and decode/2" do
    test "round-trips a key under its kind" do
      cursor = Cursor.encode(:resources, "file:///b")
      assert is_binary(cursor)
      assert {:ok, "file:///b"} = Cursor.decode(:resources, cursor)
    end

    test "is stable: the same position is the same bytes" do
      assert Cursor.encode(:resources, "x") == Cursor.encode(:resources, "x")
    end

    test "is opaque: the key is not readable in the cursor's bytes" do
      cursor = Cursor.encode(:resources, "file:///secret-name")
      refute String.contains?(cursor, "secret-name")
    end

    test "carries only URL-safe characters, so a transport never has to escape it" do
      cursor = Cursor.encode(:resources, "a b/c?d=e&f+g")
      assert cursor =~ ~r/^[A-Za-z0-9_-]+$/
    end

    test "a cursor from another list is refused by kind" do
      cursor = Cursor.encode(:tools, "t")
      assert {:error, {:kind, "tools"}} = Cursor.decode(:resources, cursor)
    end

    test "a cursor that is not base64, not JSON, not version 1 or not the shape is malformed" do
      assert {:error, :malformed} = Cursor.decode(:resources, "not base64!")

      assert {:error, :malformed} =
               Cursor.decode(:resources, Base.url_encode64("nope", padding: false))

      v2 =
        Base.url_encode64(Jason.encode!(%{"v" => 2, "k" => "resources", "a" => "x"}),
          padding: false
        )

      assert {:error, :malformed} = Cursor.decode(:resources, v2)

      no_key = Base.url_encode64(Jason.encode!(%{"v" => 1, "k" => "resources"}), padding: false)
      assert {:error, :malformed} = Cursor.decode(:resources, no_key)

      assert {:error, :malformed} = Cursor.decode(:resources, "")
      assert {:error, :malformed} = Cursor.decode(:resources, 42)
    end
  end

  describe "page/5" do
    # Items keyed by their own value; the list is given sorted, as every caller sorts it.
    test "the first page from no cursor, and nextCursor present iff something remains" do
      items = ~w(a b c d e)
      assert {~w(a b), next} = Cursor.page(:resources, items, & &1, nil, 2)
      assert {:ok, "b"} = Cursor.decode(:resources, next)
      assert {~w(c d), next2} = Cursor.page(:resources, items, & &1, {:ok, "b"}, 2)
      assert {:ok, "d"} = Cursor.decode(:resources, next2)
      assert {~w(e), nil} = Cursor.page(:resources, items, & &1, {:ok, "d"}, 2)
    end

    test "an exact fit ends without a cursor" do
      assert {~w(a b), nil} = Cursor.page(:resources, ~w(a b), & &1, nil, 2)
    end

    test "an empty list is an empty page without a cursor" do
      assert {[], nil} = Cursor.page(:resources, [], & &1, nil, 2)
    end

    test "a position whose key is no longer present still means after that key" do
      # "b" was deleted between pages: the next page starts at the first key greater than "b".
      assert {~w(c d), _} = Cursor.page(:resources, ~w(a c d e), & &1, {:ok, "b"}, 2)
    end

    test "the page is keyed on the given key function, not the item" do
      items = [%{uri: "u1", n: 1}, %{uri: "u2", n: 2}, %{uri: "u3", n: 3}]
      assert {[%{n: 2}, %{n: 3}], nil} = Cursor.page(:resources, items, & &1.uri, {:ok, "u1"}, 5)
    end
  end

  # These properties walk pages through encode/decode as the server does, so the kind and
  # the codec are exercised together.
  defp walk(items, size, kind) do
    Stream.unfold({:start, nil}, fn
      :done ->
        nil

      {_, cursor} ->
        position = if cursor, do: Cursor.decode(kind, cursor), else: nil
        {page, next} = Cursor.page(:resources, items, & &1, position, size)
        {page, if(next, do: {:next, next}, else: :done)}
    end)
    |> Enum.to_list()
  end

  property "walking every page yields exactly the sorted list, no duplicate, no gap" do
    check all(
            keys <- uniq_list_of(string(:printable, min_length: 1), max_length: 40),
            size <- integer(1..7)
          ) do
      sorted = Enum.sort(keys)
      pages = walk(sorted, size, :resources)
      assert List.flatten(pages) == sorted
      assert Enum.all?(Enum.drop(pages, -1), &(length(&1) == size))
    end
  end

  property "an item inserted between two pages never drops an item that was there before" do
    check all(
            keys <-
              uniq_list_of(string(:printable, min_length: 1), min_length: 2, max_length: 30),
            extra <- string(:printable, min_length: 1),
            size <- integer(1..5)
          ) do
      sorted = Enum.sort(keys)
      {first, next} = Cursor.page(:resources, sorted, & &1, nil, size)
      grown = Enum.sort(Enum.uniq([extra | sorted]))

      rest =
        if next do
          walk_from = fn cursor ->
            Stream.unfold({:start, cursor}, fn
              :done ->
                nil

              {_, c} ->
                {page, n} =
                  Cursor.page(:resources, grown, & &1, Cursor.decode(:resources, c), size)

                {page, if(n, do: {:next, n}, else: :done)}
            end)
            |> Enum.to_list()
            |> List.flatten()
          end

          walk_from.(next)
        else
          []
        end

      # Every original key is in the first page or in the pages after the insertion.
      assert MapSet.subset?(MapSet.new(sorted), MapSet.new(first ++ rest))
    end
  end
end
