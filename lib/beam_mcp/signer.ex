# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Signer do
  @moduledoc """
  The one seam through which a signature enters: bytes in, signature out, nothing else.

  A signer is a module implementing this behaviour. `BeamMCP.Connectome.Canonical.signature/3`
  hands it the canonical bytes `BeamMCP.Connectome.Canonical.encode/2` produces for a graph -- the bytes whose digest the
  envelope names, the bytes a verifier re-derives -- and places what comes back beside them.
  This package holds no key and calls no signing primitive; the reference implementation that
  does -- Ed25519 through OTP's `:crypto`, the key handed in by the host in the options on
  every call -- is the separate package `beam_mcp_signer`
  (github.com/ScriptKittyOS/beam_mcp_signer), which a host adds and attaches; this package does
  not depend on it. `BeamMCP.Signer.None` is the one implementation here, and it signs nothing.

  **The callback is exactly this shape, and a census pins it** (`test/beam_mcp/boundary/no_signature_test.exs`):
  two arguments, named `canonical_bytes` and `opts`; `{:ok, signature}` or `{:error, reason}`.
  Nothing else passes through it, by decision: signing bytes publishes nothing about who
  decides what, and a richer callback would. A change that needs more stops and asks; it does
  not widen.
  """

  @doc """
  Signs the canonical bytes. `opts` is whatever the host passed to
  `BeamMCP.Connectome.Canonical.signature/3` -- a key, a key id, an algorithm choice -- handed
  on whole. `BeamMCP.Connectome.Canonical.signature/3` may read `:algorithm` from it, for the
  encode, and reads nothing else. No key is guaranteed to be present: a signer reads what its
  host agreed to pass.
  """
  @callback sign(canonical_bytes :: binary(), opts :: keyword()) ::
              {:ok, binary()} | {:error, term()}
end
