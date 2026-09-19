# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/canonical.ex, which passes the file to mutate as argv[1].
#
# Msg15 -- A SECOND @behaviour BeamMCP.Signer ON A MODULE THAT IMPLEMENTS IT: Canonical becomes a signer too (round 1 lane (b) L4: pin 3 had no mutant).
import sys

p = sys.argv[1]
s = open(p).read()

old = '  defp signer?(_), do: false\n'
new = '  defp signer?(_), do: false\n\n  @behaviour BeamMCP.Signer\n  @impl BeamMCP.Signer\n  def sign(_canonical_bytes, _opts), do: {:error, :no_signer}\n'

if s.count(old) != 1:
    sys.exit("Msg15: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
