# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Signer.None do
  @moduledoc """
  The signer that signs nothing: `{:error, :no_signer}`, whatever the bytes and options.

  The one implementation of `BeamMCP.Signer` in this package, and the one `sign/2` a census
  allows under `lib/`, spelled exactly as it is here. It exists so that a host's wiring can
  name a signer before it has one, and so that the seam is exercised by a module that holds no
  key -- the real one is `beam_mcp_signer`.
  """
  @behaviour BeamMCP.Signer

  @doc "Signs nothing: `{:error, :no_signer}`, whatever the bytes and options."
  @impl true
  def sign(_canonical_bytes, _opts), do: {:error, :no_signer}
end
