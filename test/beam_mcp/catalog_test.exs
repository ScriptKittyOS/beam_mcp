# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.CatalogTest do
  use ExUnit.Case, async: true

  alias BeamMCP.{Catalog, Server, ToolSpec}

  defp spec(name) do
    %ToolSpec{name: name, command_class: :observe, mode: :read_only, description: "d"}
  end

  defmodule OnlyHere do
    @behaviour BeamMCP.Catalog
    @impl true
    def capabilities do
      %{
        tools: [
          %BeamMCP.ToolSpec{
            name: :only_in_this_catalog,
            command_class: :observe,
            mode: :read_only,
            description: "Exists in no other catalog."
          }
        ],
        resources: [],
        prompts: []
      }
    end
  end

  describe "the single-lookup guarantee" do
    # Slice 002 fixed a real defect: `tools/list` honoured the injected catalog and
    # `tools/call` consulted a different source, so a tool could be advertised and refused.
    # `Catalog.tools/1` is now the one reader and both paths go through it. This pins that by
    # EFFECT -- the two answers are compared against each other, not against a constant -- and
    # the catalog's tool exists in no other catalog in this suite, so neither path can pass by
    # coincidence the way slice 002's original test did.
    test "what tools/list advertises is exactly what tools/call will accept" do
      state = Server.new(catalog: OnlyHere, dispatch: fn _n, a, _o -> {:ok, a} end)

      {_state, listed} =
        Server.handle_message(state, %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "tools/list"
        })

      advertised = listed["result"]["tools"] |> Enum.map(& &1["name"]) |> Enum.sort()

      callable =
        for name <- advertised do
          {_s, r} =
            Server.handle_message(state, %{
              "jsonrpc" => "2.0",
              "id" => 2,
              "method" => "tools/call",
              "params" => %{"name" => name, "arguments" => %{}}
            })

          if Map.has_key?(r, "result"), do: name
        end
        |> Enum.reject(&is_nil/1)
        |> Enum.sort()

      assert advertised == ["only_in_this_catalog"]
      assert callable == advertised
    end

    test "a name the catalog does not advertise is not callable either" do
      state = Server.new(catalog: OnlyHere, dispatch: fn _n, a, _o -> {:ok, a} end)

      {_s, r} =
        Server.handle_message(state, %{
          "jsonrpc" => "2.0",
          "id" => 3,
          "method" => "tools/call",
          "params" => %{"name" => "not_advertised", "arguments" => %{}}
        })

      assert r["error"]["code"] == -32_601
    end

    test "Catalog.tools/1 and Catalog.fetch/2 read the same source" do
      # The structural half of the same guarantee: fetch resolves exactly the specs tools/1
      # returns, so a mutant giving them different sources has something to break.
      names = OnlyHere |> Catalog.tools() |> Enum.map(& &1.name)

      for n <- names do
        assert {:ok, %ToolSpec{name: ^n}} = Catalog.fetch(OnlyHere, n)
      end

      assert Catalog.fetch(OnlyHere, "absent") == :error
    end
  end

  describe "a malformed catalog is refused at new/1, not at the first request" do
    defmodule MissingPrompts do
      def capabilities, do: %{tools: [], resources: []}
    end

    defmodule ToolsNotAList do
      def capabilities, do: %{tools: %{}, resources: [], prompts: []}
    end

    defmodule NotSpecs do
      def capabilities, do: %{tools: [%{name: :echo}], resources: [], prompts: []}
    end

    defmodule NotAMap do
      def capabilities, do: [:tools]
    end

    defmodule NoCallback do
      def unrelated, do: :ok
    end

    test "an absent key is a malformed catalog, not an empty one" do
      assert_raise ArgumentError, ~r/missing required key\(s\): \[:prompts\]/, fn ->
        Server.new(catalog: MissingPrompts)
      end
    end

    test ":tools must be a list" do
      assert_raise ArgumentError, ~r/:tools must be a list/, fn ->
        Server.new(catalog: ToolsNotAList)
      end
    end

    test ":tools entries must be %ToolSpec{}" do
      # This one is the silent failure the @spec probe found: fetch/2 RETURNS a bare map
      # happily, so without this check a malformed entry reaches dispatch as a struct-shaped
      # thing that is not a struct.
      assert_raise ArgumentError, ~r/must all be %BeamMCP.ToolSpec\{\}/, fn ->
        Server.new(catalog: NotSpecs)
      end
    end

    test "capabilities/0 must return a map" do
      assert_raise ArgumentError, ~r/must return a map/, fn ->
        Server.new(catalog: NotAMap)
      end
    end

    test "a module that does not export capabilities/0 is refused" do
      assert_raise ArgumentError, ~r/does not export capabilities\/0/, fn ->
        Server.new(catalog: NoCallback)
      end
    end
  end

  describe "Catalog.validate/1 reports rather than raises" do
    test "a good catalog is :ok" do
      assert Catalog.validate(OnlyHere) == :ok
    end

    test "a non-module is refused with the value it got" do
      assert {:error, msg} = Catalog.validate("not a module")
      assert msg =~ "expected a module"
    end
  end

  describe "fetch/2's documented raise conditions, held to what was measured" do
    defmodule BinaryName do
      def capabilities do
        %{
          tools: [
            %BeamMCP.ToolSpec{
              name: "echo",
              command_class: :observe,
              mode: :read_only,
              description: "d"
            }
          ],
          resources: [],
          prompts: []
        }
      end
    end

    test "a binary spec.name raises rather than returning :error" do
      # The @spec says {:ok, t} | :error and this raises. That is DOCUMENTED rather than
      # caught, because catching would make a host bug indistinguishable from "no such tool" --
      # the advertise-versus-call confusion this behaviour exists to prevent. The moduledoc
      # lists the measured conditions; this pins one of them so the list cannot go stale
      # silently.
      assert_raise ArgumentError, fn -> Catalog.fetch(BinaryName, "echo") end
    end

    test "an unloaded module raises" do
      assert_raise UndefinedFunctionError, fn -> Catalog.fetch(NoSuchCatalogAnywhere, "echo") end
    end
  end

  test "the spec/1 helper is unused elsewhere and exists only to keep this file readable" do
    assert %ToolSpec{name: :x} = spec(:x)
  end
end
