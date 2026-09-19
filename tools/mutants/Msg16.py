# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/catalog.ex, which passes the file to mutate as argv[1].
#
# Msg16 -- A HIDDEN CALLBACK OF THE SEAM'S SHAPE ON AN ALLOWED BEHAVIOUR: @doc false @callback attest/2 on BeamMCP.Catalog (round 2 lane (b) M1: passed the whole suite before the callback-list pin).
import sys

p = sys.argv[1]
s = open(p).read()

old = '  @optional_callbacks read_resource: 1, get_prompt: 2\n'
new = '  @doc false\n  @callback attest(canonical_bytes :: binary(), opts :: keyword()) ::\n              {:ok, binary()} | {:error, term()}\n\n  @optional_callbacks read_resource: 1, get_prompt: 2, attest: 2\n'

if s.count(old) != 1:
    sys.exit("Msg16: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
