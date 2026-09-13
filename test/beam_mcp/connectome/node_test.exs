# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Connectome.NodeTest do
  use ExUnit.Case, async: true

  alias BeamMCP.Connectome.Node

  describe "Node.new/1" do
    test "builds a tool node with a structural id and its labels" do
      assert {:ok, %Node{} = node} =
               Node.new(
                 kind: :tool,
                 level: :server,
                 identity: {:tool, "srv", :echo},
                 labels: %{command_class: :observe, mode: :read_only}
               )

      assert node.id == Node.id({:tool, "srv", :echo})
      assert node.kind == :tool
      assert node.level == :server
      assert node.labels == %{command_class: :observe, mode: :read_only}
    end

    test "the level is the level given, never inferred from the kind" do
      # Every other test builds a catalog node at :server, and a mutant that silently set the
      # level of every :tool node to :server survived them all. The field is what the caller
      # said, whatever the kind; :module and :server are members of both families and the
      # struct must never derive one field from the other.
      for kind <- [:tool, :resource, :prompt, :process], level <- [:mfa, :module, :boundary] do
        assert {:ok, %Node{kind: ^kind, level: ^level}} =
                 Node.new(kind: kind, level: level, identity: {kind, "srv", :x})
      end
    end

    test "labels default to an empty map" do
      assert {:ok, %Node{labels: %{}}} =
               Node.new(kind: :server, level: :server, identity: {:server, "srv"})
    end

    test "an invalid kind is refused with a named error" do
      assert {:error, {:invalid, :kind, :neuron}} =
               Node.new(kind: :neuron, level: :server, identity: {:server, "srv"})
    end

    test "an invalid level is refused with a named error" do
      assert {:error, {:invalid, :level, :neuropil}} =
               Node.new(kind: :module, level: :neuropil, identity: {:module, "srv", Enum})
    end

    test "an identity whose tag is not the node's kind is refused" do
      assert {:error, {:invalid, :identity, {:tool, "srv", :echo}}} =
               Node.new(kind: :resource, level: :server, identity: {:tool, "srv", :echo})
    end

    test "a missing required key is refused by name" do
      assert {:error, {:missing, :identity}} = Node.new(kind: :server, level: :server)
      assert {:error, {:missing, :kind}} = Node.new(level: :server, identity: {:server, "srv"})
      assert {:error, {:missing, :level}} = Node.new(kind: :server, identity: {:server, "srv"})
    end

    test "an unknown key is refused by name, so a field cannot arrive unannounced" do
      assert {:error, {:unknown_key, :sign}} =
               Node.new(kind: :server, level: :server, identity: {:server, "srv"}, sign: :allow)
    end

    test "labels must be a map" do
      assert {:error, {:invalid, :labels, [:a]}} =
               Node.new(kind: :server, level: :server, identity: {:server, "srv"}, labels: [:a])
    end

    test "new!/1 raises the same named reason" do
      assert_raise ArgumentError, ~r/\{:invalid, :kind, :neuron\}/, fn ->
        Node.new!(kind: :neuron, level: :server, identity: {:server, "srv"})
      end

      assert %Node{} = Node.new!(kind: :server, level: :server, identity: {:server, "srv"})
    end
  end

  describe "Node.id/1 -- one function, one implementation site" do
    test "is a string, stable across calls, and distinct across identities" do
      a = Node.id({:tool, "srv", :echo})
      assert is_binary(a)
      assert a == Node.id({:tool, "srv", :echo})
      assert a != Node.id({:tool, "other", :echo})
      assert a != Node.id({:resource, "srv", :echo})
      assert a != Node.id({:tool, "srv", :echo2})
    end

    test "covers every identity shape the vocabulary names" do
      ids = [
        Node.id({:server, "srv"}),
        Node.id({:tool, "srv", :echo}),
        Node.id({:resource, "srv", "file:///etc/hosts"}),
        Node.id({:prompt, "srv", :greet}),
        Node.id({:process, "srv", :my_worker}),
        Node.id({:module, "srv", Enum}),
        Node.id({:module, "srv", {Enum, :map, 2}})
      ]

      assert Enum.all?(ids, &is_binary/1)
      assert length(Enum.uniq(ids)) == length(ids)
    end

    test "a name that is a string and the same name as an atom are the same node" do
      assert Node.id({:tool, "srv", :echo}) == Node.id({:tool, "srv", "echo"})
    end

    test "an identity shape the vocabulary does not name is refused" do
      assert_raise ArgumentError, ~r/identity/, fn -> Node.id({:neuron, "srv", :x}) end
      assert_raise ArgumentError, ~r/identity/, fn -> Node.id({:tool, "srv"}) end
    end

    test "the server component must be a string" do
      assert_raise ArgumentError, ~r/server/, fn -> Node.id({:tool, :srv, :echo}) end
    end
  end
end
