# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/signer/none.ex, which passes the file to mutate as argv[1].
#
# Msg14 -- A SECOND DEFINITION OF sign HIDING BEHIND A PARENTHESIS: def(sign(...)) beside the no-op (round 1 lane (b) M2).
import sys

p = sys.argv[1]
s = open(p).read()

old = '  def sign(_canonical_bytes, _opts), do: {:error, :no_signer}\n'
new = '  def sign(_canonical_bytes, _opts), do: {:error, :no_signer}\n\n  @doc false\n  def(sign(canonical_bytes, _opts, _key), do: {:ok, canonical_bytes})\n'

if s.count(old) != 1:
    sys.exit("Msg14: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
