# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Fixture.Signer do
  @moduledoc false
  # Signers for the seam's tests, none holding a key: one that "signs" by echoing a digest of
  # the bytes it was handed (so a test can prove which bytes reached it), one that refuses,
  # one that answers a non-binary, one that raises, and one that is not a signer at all.
  defmodule Echo do
    @moduledoc false
    @behaviour BeamMCP.Signer
    @impl true
    def sign(canonical_bytes, opts) do
      send(self(), {:signed, canonical_bytes, opts})
      {:ok, :crypto.hash(:sha256, canonical_bytes)}
    end
  end

  defmodule Refuses do
    @moduledoc false
    @behaviour BeamMCP.Signer
    @impl true
    def sign(_canonical_bytes, _opts), do: {:error, :key_absent}
  end

  defmodule NotABinary do
    @moduledoc false
    @behaviour BeamMCP.Signer
    @impl true
    def sign(_canonical_bytes, _opts), do: {:ok, :not_bytes}
  end

  defmodule Raises do
    @moduledoc false
    @behaviour BeamMCP.Signer
    @impl true
    def sign(_canonical_bytes, _opts), do: raise("the host's signer blew up")
  end

  defmodule NotASigner do
    @moduledoc false
    def something_else, do: :ok
  end
end
