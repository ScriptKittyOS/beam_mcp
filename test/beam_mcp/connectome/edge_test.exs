# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Connectome.EdgeTest do
  use ExUnit.Case, async: true

  alias BeamMCP.Connectome.{Edge, Node}

  @from Node.id({:server, "srv"})
  @to Node.id({:tool, "srv", :echo})

  describe "Edge.new/1" do
    test "builds an edge whose sign is :unknown, because the package writes nothing else" do
      assert {:ok, %Edge{} = edge} =
               Edge.new(from: @from, to: @to, kind: :invoke, provenance: :declared)

      assert edge.sign == :unknown
      assert edge.weight == nil
      assert {edge.from, edge.to, edge.kind, edge.provenance} == {@from, @to, :invoke, :declared}
    end

    test "carries a weight when given one" do
      assert {:ok, %Edge{weight: 3}} =
               Edge.new(from: @from, to: @to, kind: :invoke, provenance: :observed, weight: 3)
    end

    test ":sign is not an accepted key -- there is no way in through the constructor" do
      assert {:error, {:unknown_key, :sign}} =
               Edge.new(from: @from, to: @to, kind: :invoke, provenance: :declared, sign: :allow)

      assert {:error, {:unknown_key, :sign}} =
               Edge.new(
                 from: @from,
                 to: @to,
                 kind: :invoke,
                 provenance: :declared,
                 sign: :unknown
               )
    end

    test "an invalid kind is refused with a named error" do
      assert {:error, {:invalid, :kind, :teleport}} =
               Edge.new(from: @from, to: @to, kind: :teleport, provenance: :declared)
    end

    test "an invalid provenance is refused with a named error" do
      assert {:error, {:invalid, :provenance, :guessed}} =
               Edge.new(from: @from, to: @to, kind: :invoke, provenance: :guessed)
    end

    test "endpoints must be node ids (strings)" do
      assert {:error, {:invalid, :from, :srv}} =
               Edge.new(from: :srv, to: @to, kind: :invoke, provenance: :declared)

      assert {:error, {:invalid, :to, 7}} =
               Edge.new(from: @from, to: 7, kind: :invoke, provenance: :declared)
    end

    test "a weight must be nil or a non-negative number" do
      assert {:error, {:invalid, :weight, -1}} =
               Edge.new(from: @from, to: @to, kind: :invoke, provenance: :observed, weight: -1)

      assert {:error, {:invalid, :weight, "3"}} =
               Edge.new(from: @from, to: @to, kind: :invoke, provenance: :observed, weight: "3")
    end

    test "a missing required key is refused by name" do
      assert {:error, {:missing, :provenance}} = Edge.new(from: @from, to: @to, kind: :invoke)
      assert {:error, {:missing, :kind}} = Edge.new(from: @from, to: @to, provenance: :declared)
      assert {:error, {:missing, :from}} = Edge.new(to: @to, kind: :invoke, provenance: :declared)

      assert {:error, {:missing, :to}} =
               Edge.new(from: @from, kind: :invoke, provenance: :declared)
    end

    test "new!/1 raises the same named reason" do
      assert_raise ArgumentError, ~r/\{:unknown_key, :sign\}/, fn ->
        Edge.new!(from: @from, to: @to, kind: :invoke, provenance: :declared, sign: :deny)
      end
    end
  end

  test "options that are not a keyword list are refused by name, not by a clause error" do
    assert {:error, {:invalid, :opts, %{}}} = Edge.new(%{})
    assert {:error, {:invalid, :opts, [{"from", 1}]}} = Edge.new([{"from", 1}])
    assert_raise ArgumentError, ~r/\{:invalid, :opts, nil\}/, fn -> Edge.new!(nil) end
  end

  describe "Edge.key/1" do
    test "is the identity of an edge: from, to, kind, provenance -- never sign or weight" do
      {:ok, a} = Edge.new(from: @from, to: @to, kind: :invoke, provenance: :declared, weight: 1)
      {:ok, b} = Edge.new(from: @from, to: @to, kind: :invoke, provenance: :declared, weight: 9)
      assert Edge.key(a) == Edge.key(b)
      assert Edge.key(a) == {@from, @to, :invoke, :declared}
    end
  end
end
