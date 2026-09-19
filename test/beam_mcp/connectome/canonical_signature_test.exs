# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Connectome.CanonicalSignatureTest do
  @moduledoc """
  The seam: `Canonical.signature/3` hands `encode/2`'s bytes to a host-supplied signer and
  returns what comes back beside them. The bytes it hands over are exactly the bytes a
  verifier re-derives; the envelope does not move; the package reads only `:algorithm` from
  the options and the signer reads the rest.
  """
  use ExUnit.Case, async: true

  alias BeamMCP.Connectome.{Canonical, Edge, Graph, Node}
  alias BeamMCP.Fixture.Signer

  defp graph do
    srv = Node.new!(kind: :server, level: :server, identity: {:server, "srv"})
    a = Node.new!(kind: :tool, level: :server, identity: {:tool, "srv", "a"})
    b = Node.new!(kind: :tool, level: :server, identity: {:tool, "srv", "b"})

    e =
      Edge.new!(from: a.id, to: b.id, kind: :invoke, provenance: :declared, weight: 1)

    Graph.new!(nodes: [srv, a, b], edges: [e], schema_version: Graph.schema_version())
  end

  test "the signer receives exactly encode/2's bytes, with the host's options, and the result sits beside them" do
    g = graph()
    {:ok, bytes} = Canonical.encode(g)
    assert {:ok, result} = Canonical.signature(g, Signer.Echo, key_id: "k1")
    assert_received {:signed, ^bytes, [key_id: "k1"]}

    assert result == %{
             algorithm: :sha256,
             signature: :crypto.hash(:sha256, bytes),
             signer: Signer.Echo
           }

    # The envelope did not move: encoding again gives the same bytes, signature or not.
    assert Canonical.encode(g) == {:ok, bytes}
  end

  test "the algorithm option reaches the encode, is named in the result, and is what the signer sees in its bytes" do
    g = graph()
    {:ok, bytes384} = Canonical.encode(g, algorithm: :sha384)

    assert {:ok, %{algorithm: :sha384, signature: sig}} =
             Canonical.signature(g, Signer.Echo, algorithm: :sha384)

    assert_received {:signed, ^bytes384, [algorithm: :sha384]}
    assert sig == :crypto.hash(:sha256, bytes384)
    assert bytes384 =~ ~s("algorithm":"sha384")
  end

  test "the no-op is a refusal by name, not a signature" do
    assert Canonical.signature(graph(), BeamMCP.Signer.None) == {:error, {:signer, :no_signer}}
  end

  test "a signer's refusal is passed on under its name; a non-binary answer is refused; a module that is no signer is refused before any encode" do
    assert Canonical.signature(graph(), Signer.Refuses) == {:error, {:signer, :key_absent}}

    assert Canonical.signature(graph(), Signer.NotABinary) ==
             {:error, {:signer, {:not_a_signature, :not_bytes}}}

    assert Canonical.signature(graph(), Signer.NotASigner) ==
             {:error, {:signer, {:not_a_signer, Signer.NotASigner}}}

    assert Canonical.signature(graph(), NoSuch.Module) ==
             {:error, {:signer, {:not_a_signer, NoSuch.Module}}}

    assert Canonical.signature(graph(), "not a module") ==
             {:error, {:signer, {:not_a_signer, "not a module"}}}

    assert Canonical.signature(graph(), nil) == {:error, {:signer, {:not_a_signer, nil}}}
  end

  test "an encode refusal is the encode's, and the signer is never called" do
    bad = %Graph{graph() | edges: [%Edge{hd(graph().edges) | provenance: :guessed}]}
    assert {:error, {:uncanonical, _}} = Canonical.signature(bad, Signer.Echo)
    refute_received {:signed, _, _}
  end

  test "a signer that raises, raises: it is the host's code" do
    assert_raise RuntimeError, ~r/blew up/, fn -> Canonical.signature(graph(), Signer.Raises) end
  end

  test "an unknown option is the encode's refusal, as encode/2 gives it, before the signer sees anything" do
    assert_raise ArgumentError, ~r/algorithm/, fn ->
      Canonical.signature(graph(), Signer.Echo, algorithm: :md5)
    end

    refute_received {:signed, _, _}
  end
end
