# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/canonical.ex, which passes the file to mutate as argv[1].
#
# Msg9 -- THE RESULT NAMES THE DEFAULT ALGORITHM WHATEVER WAS ENCODED.
import sys

p = sys.argv[1]
s = open(p).read()

old = '          {:ok, %{algorithm: algorithm!(encode_opts), signature: sig, signer: signer}}'
new = '          {:ok, %{algorithm: :sha256, signature: sig, signer: signer}}'

if s.count(old) != 1:
    sys.exit("Msg9: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
