# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Boundary.NoKeyHoldingTest do
  # boundary: holds no key
  # The package holds no key: no line under lib/ generates, loads, decodes or stores key
  # material. The one cryptographic call it makes is `:crypto.hash/2`, a digest over bytes
  # with no key in it; every other `:crypto.` and every `:public_key.` call is refused by this
  # census, as is any name that reads as key material -- including `Plug.Crypto`, the key
  # derivation and signing library `plug` brings into the lock file, which is not `:crypto` by
  # name. Key material by any other name -- an environment variable, a `_KEY` constant -- is
  # barred by the way it would be loaded, since a census cannot know what a binary is (the
  # tracer keeps its running flag in `:persistent_term`, so the store itself is not barred). And
  # `:crypto.hash/2` is called at exactly ONE site, the canonical module's `digest/2`, with the
  # algorithm a variable bound from the caller's option (`:sha256`, `:sha384` or `:sha512`, the
  # envelope naming which) and never a literal -- until the algorithm joined the bytes there
  # were two sites, each spelling `:sha256`; a second site now must say what it hashes and why
  # the one site does not serve.
  use ExUnit.Case, async: true
  alias BeamMCP.Boundary

  @key_material ~r/generate_key|private_key|secret_key|signing_key|_KEY\b|hmac|pem_decode|pem_entry_decode|der_decode|:public_key\.|strong_rand_bytes|JOSE|jose|jwk|Plug\.Crypto|KeyGenerator|System\.(get_env|fetch_env!?)\(/
  @crypto_call ~r/:crypto\.(?!hash\()/

  test "no line under lib/ names key material or calls a crypto function other than :crypto.hash/2" do
    hits = Enum.uniq(Boundary.hits(@key_material) ++ Boundary.hits(@crypto_call))
    assert hits == [], "key material under lib/:\n  " <> Boundary.format(hits)
    # And the census sees something: the digest call is there, so the reader is not empty.
    assert Boundary.hits(~r/:crypto\.hash\(/) != []
  end

  test ":crypto.hash/2 is called at one site, over canonical bytes, with the algorithm a variable" do
    sites = Boundary.hits(~r/:crypto\.hash\(/)
    assert length(sites) == 1, "sites:\n  " <> Boundary.format(sites)
    assert [{"lib/beam_mcp/connectome/canonical.ex", _line, text}] = sites
    assert text =~ ":crypto.hash(algorithm, bytes)"
    # No digest is spelled as a literal anywhere under lib/ outside the list the option is
    # checked against: the choice is the caller's and the page's, not a file's.
    assert Boundary.hits(~r/:crypto\.hash\(:sha/) == []
  end
end
