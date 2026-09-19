# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/signer.ex, which passes the file to mutate as argv[1].
#
# Msg1 -- A SECOND CALLBACK BESIDE sign/2 (optional, so the no-op still compiles): the seam widens to a verify.
import sys

p = sys.argv[1]
s = open(p).read()

old = '  @callback sign(canonical_bytes :: binary(), opts :: keyword()) ::\n'
new = '  @callback verify(canonical_bytes :: binary(), signature :: binary()) :: boolean()\n  @optional_callbacks verify: 2\n  @callback sign(canonical_bytes :: binary(), opts :: keyword()) ::\n'

if s.count(old) != 1:
    sys.exit("Msg1: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
