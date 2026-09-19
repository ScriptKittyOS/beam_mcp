# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/signer/none.ex, which passes the file to mutate as argv[1].
#
# Msg4 -- THE NO-OP SIGNS: a :crypto.sign call under lib/ with a key from the options.
import sys

p = sys.argv[1]
s = open(p).read()

old = '  def sign(_canonical_bytes, _opts), do: {:error, :no_signer}'
new = '  def sign(canonical_bytes, opts), do: {:ok, :crypto.sign(:eddsa, :none, canonical_bytes, [opts[:key], :ed25519])}'

if s.count(old) != 1:
    sys.exit("Msg4: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
