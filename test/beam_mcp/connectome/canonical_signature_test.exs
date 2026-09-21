# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Connectome.CanonicalSignatureTest do
  @moduledoc """
  The seam: `Canonical.signature/3` hands `encode/2`'s bytes to a host-supplied signer and
  returns what comes back beside them. The bytes it hands over are exactly the bytes a
  verifier re-derives; the envelope does not move; the package reads `:algorithm` from the
  options for the encode, copies `:scheme` and `:key_id` beside the result, and reads nothing
  else -- the signer reads the rest.
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

    # Five members: the three since 0.7.0 and, beside the signature, the scheme and the key id
    # copied from the host's options -- `nil` here, since this host passed no scheme.
    assert result == %{
             algorithm: :sha256,
             signature: :crypto.hash(:sha256, bytes),
             signer: Signer.Echo,
             scheme: nil,
             key_id: "k1"
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

  test "scheme: and key_id: come back as the host passed them, nil when it passed neither, and the signer sees them too" do
    g = graph()
    {:ok, bytes} = Canonical.encode(g)

    assert {:ok, both} = Canonical.signature(g, Signer.Echo, scheme: :ed25519, key_id: "k-2026")
    assert both.scheme == :ed25519
    assert both.key_id == "k-2026"
    assert Map.keys(both) |> Enum.sort() == [:algorithm, :key_id, :scheme, :signature, :signer]
    # The options reach the signer whole, the two members among them: the signer that holds
    # the key reads them; this package copies them.
    assert_received {:signed, ^bytes, [scheme: :ed25519, key_id: "k-2026"]}

    assert {:ok, neither} = Canonical.signature(g, Signer.Echo)
    assert %{scheme: nil, key_id: nil} = neither

    assert {:ok, one} = Canonical.signature(g, Signer.Echo, scheme: :ecdsa_p384_sha384)
    assert %{scheme: :ecdsa_p384_sha384, key_id: nil} = one

    assert {:ok, other} = Canonical.signature(g, Signer.Echo, key_id: <<1, 2, 3>>)
    assert %{scheme: nil, key_id: <<1, 2, 3>>} = other
  end

  test "the scheme rides beside the bytes, never inside them: bytes, hash and the signer's input are the same with or without it" do
    g = graph()
    {:ok, bytes} = Canonical.encode(g)
    {:ok, hash} = Canonical.hash(g)

    for opts <- [
          [],
          [scheme: :ed25519],
          [scheme: :mldsa87, key_id: "k"],
          [algorithm: :sha384, scheme: :ed25519]
        ] do
      {encode_opts, _} = Keyword.split(opts, [:algorithm])
      {:ok, expected} = Canonical.encode(g, encode_opts)
      assert {:ok, %{signature: sig}} = Canonical.signature(g, Signer.Echo, opts)
      assert_received {:signed, ^expected, ^opts}
      assert sig == :crypto.hash(:sha256, expected)
      refute expected =~ "scheme"
      refute expected =~ "key_id"
    end

    # And the default-algorithm bytes and hash did not move for having been signed under a scheme.
    assert Canonical.encode(g) == {:ok, bytes}
    assert Canonical.hash(g) == {:ok, hash}
  end

  test "the three scheme names are the vocabulary the type names, and the package verifies none of them" do
    # The type is the vocabulary the companion signer package uses; docs/connectome.md defines
    # each (the vocabulary test holds the @type to the page). The package copies what the host
    # asserts and refuses nothing here: the binding of a key id to an algorithm is the
    # consumer's registry's, not this package's.
    {:ok, types} = Code.Typespec.fetch_types(Canonical)
    [{:scheme, spec, []}] = for {:type, {:scheme, _, _} = t} <- types, do: t

    assert Macro.to_string(Code.Typespec.type_to_quoted({:scheme, spec, []})) ==
             "scheme() :: :ed25519 | :ecdsa_p384_sha384 | :mldsa87"

    for scheme <- [:ed25519, :ecdsa_p384_sha384, :mldsa87, :not_a_scheme_the_page_names] do
      assert {:ok, %{scheme: ^scheme}} = Canonical.signature(graph(), Signer.Echo, scheme: scheme)
    end
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
