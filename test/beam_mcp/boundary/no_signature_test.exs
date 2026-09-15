# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Boundary.NoSignatureTest do
  # boundary: makes no signature
  # The package makes no signature: no signing or MAC primitive is called under lib/, and no
  # function named `sign` is defined there. Signing canonical bytes is a separate package's
  # (`sign(bytes, opts)`, decided); the `sign` field an edge carries is the host's verdict slot,
  # a data field the package writes `:unknown` into -- a value, not an act -- so the pattern
  # bars the act (a call, a `def sign`, a signer behaviour) and not the word.
  use ExUnit.Case, async: true
  alias BeamMCP.Boundary

  @signing ~r/:crypto\.(sign|mac|mac_init|hmac)|:public_key\.sign|Signature|\bdef\s+sign\b|\bdefp\s+sign\b|\bsign!\(|@behaviour\s+\S*Signer/

  test "no line under lib/ calls a signing or MAC primitive or defines a sign function" do
    hits = Boundary.hits(@signing)
    assert hits == [], "signing under lib/:\n  " <> Boundary.format(hits)
  end
end
