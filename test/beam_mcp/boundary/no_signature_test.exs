# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Boundary.NoSignatureTest do
  # boundary: makes no signature of its own -- the seam is one callback, pinned
  #
  # The package makes no signature of its own: no signing or MAC primitive is called under
  # lib/, and no key is held (the no-key census). What it has instead is ONE seam, decided by
  # the owner (CX-079) and pinned here so that widening it is a visible act:
  #
  #   - `BeamMCP.Signer`, a behaviour with exactly one callback,
  #     `sign(canonical_bytes :: binary(), opts :: keyword()) :: {:ok, binary()} | {:error, term()}`
  #     -- two arguments, those names. Bytes in, signature out, nothing else: no verdict, no
  #     chain position, no prior hash, no hold, no approval, no witness, no receipt shape;
  #   - `BeamMCP.Signer.None`, the one no-op allowed under lib/, `{:error, :no_signer}`;
  #   - `BeamMCP.Connectome.Canonical.signature/3`, the one site that calls a signer, over the
  #     bytes `encode/2` produces, returning the signature beside them and moving no byte.
  #
  # The key and the primitive live in a separate package (`beam_mcp_signer`); a host hands
  # its key to that package, never to this one. The `sign` field an edge carries is the
  # host's verdict slot, a value not an act (will-not-implement entry 1), and is outside this
  # census. `Plug.Crypto` (`MessageVerifier.sign/2`, an HMAC) is in the lock file through
  # `plug` and stays barred by name: a dependency's signer is still a signer.
  use ExUnit.Case, async: true
  alias BeamMCP.Boundary
  alias BeamMCP.Signer

  @primitive ~r/:crypto\.(sign|mac|mac_init|hmac)|:public_key\.sign|Signature\.|\bsign!\(|Plug\.Crypto|MessageVerifier/
  @none_file "lib/beam_mcp/signer/none.ex"
  @none_line "def sign(_canonical_bytes, _opts), do: {:error, :no_signer}"
  @seam_file "lib/beam_mcp/connectome/canonical.ex"
  @seam_call "signer.sign(bytes, opts)"

  test "no line under lib/ calls a signing or MAC primitive" do
    hits = Boundary.hits(@primitive)
    assert hits == [], "a signing primitive under lib/:\n  " <> Boundary.format(hits)
  end

  test "exactly one `def sign` under lib/: the no-op, spelled as pinned, in its own file" do
    hits = Boundary.hits(~r/\bdefp?\s+sign\b/)

    assert [{@none_file, _, line}] = hits,
           "def sign sites under lib/:\n  " <> Boundary.format(hits)

    assert String.trim(line) == @none_line
  end

  test "exactly one `@behaviour BeamMCP.Signer` under lib/: the no-op" do
    hits = Boundary.hits(~r/@behaviour\s+\S*Signer\b/)

    assert [{@none_file, _, line}] = hits,
           "signer behaviours under lib/:\n  " <> Boundary.format(hits)

    assert String.trim(line) == "@behaviour BeamMCP.Signer"
  end

  test "the behaviour has exactly one callback, sign/2, with the pinned argument names and return" do
    assert Code.ensure_loaded?(BeamMCP.Signer)
    assert BeamMCP.Signer.behaviour_info(:callbacks) == [sign: 2]

    {:ok, callbacks} = Code.Typespec.fetch_callbacks(BeamMCP.Signer)
    assert [{{:sign, 2}, [spec]}] = callbacks

    {:type, _, :fun, [{:type, _, :product, args}, ret]} = spec

    names =
      Enum.map(args, fn
        {:ann_type, _, [{:var, _, name}, _type]} -> name
        {:var, _, name} -> name
        other -> {:unnamed, other}
      end)

    assert names == [:canonical_bytes, :opts]

    assert Macro.to_string(Code.Typespec.type_to_quoted({:t, ret, []})) =~
             ~r/\{:ok, binary\(\)\} \| \{:error, term\(\)\}/
  end

  test "exactly one call of a signer under lib/: signature/3's, over encode/2's bytes" do
    # `Edge.sign()` in a typespec is the verdict slot's type, not a call: the pattern wants
    # arguments between the parentheses.
    hits = Boundary.hits(~r/\.sign\((?!\))/)
    assert [{@seam_file, _, line}] = hits, ".sign( sites under lib/:\n  " <> Boundary.format(hits)
    assert String.contains?(line, @seam_call)
  end

  test "the no-op answers {:error, :no_signer} and never reads its arguments" do
    assert Signer.None.sign(<<1, 2, 3>>, []) == {:error, :no_signer}
    assert Signer.None.sign("", key: "not read") == {:error, :no_signer}
  end
end
