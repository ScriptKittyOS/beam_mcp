# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Boundary.NoKeyHoldingTest do
  # boundary: holds no key
  # The package holds no key: no line under lib/ generates, loads, decodes or stores key
  # material. The one cryptographic call it makes is `:crypto.hash/2`, a digest over bytes
  # with no key in it; every other `:crypto.` and every `:public_key.` call is refused by this
  # census, as is any name that reads as key material.
  use ExUnit.Case, async: true
  alias BeamMCP.Boundary

  @key_material ~r/generate_key|private_key|secret_key|pem_decode|pem_entry_decode|der_decode|:public_key\.|strong_rand_bytes|JOSE|jose|jwk/
  @crypto_call ~r/:crypto\.(?!hash\()/

  test "no line under lib/ names key material or calls a crypto function other than :crypto.hash/2" do
    hits = Enum.uniq(Boundary.hits(@key_material) ++ Boundary.hits(@crypto_call))
    assert hits == [], "key material under lib/:\n  " <> Boundary.format(hits)
    # And the census sees something: the digest call is there, so the reader is not empty.
    assert Boundary.hits(~r/:crypto\.hash\(/) != []
  end
end
