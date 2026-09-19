# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/signer.ex, which passes the file to mutate as argv[1].
#
# Msg12 -- A SECOND BEHAVIOUR OF THE SEAM'S SHAPE: BeamMCP.Signer2, the same callback, @moduledoc false (round 1 lane (b) H1: passed the whole suite before the behaviour-set pin).
import sys

p = sys.argv[1]
s = open(p).read()

old = '              {:ok, binary()} | {:error, term()}\nend\n'
new = '              {:ok, binary()} | {:error, term()}\nend\n\ndefmodule BeamMCP.Signer2 do\n  @moduledoc false\n  @callback sign(canonical_bytes :: binary(), opts :: keyword()) ::\n              {:ok, binary()} | {:error, term()}\nend\n'

if s.count(old) != 1:
    sys.exit("Msg12: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
