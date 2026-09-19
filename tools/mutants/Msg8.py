# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/canonical.ex, which passes the file to mutate as argv[1].
#
# Msg8 -- THE SIGNER GETS THE DIGEST, NOT THE BYTES: what is signed is no longer what a verifier re-derives.
import sys

p = sys.argv[1]
s = open(p).read()

old = '      case signer.sign(bytes, opts) do'
new = '      case signer.sign(:crypto.hash(:sha256, bytes), opts) do'

if s.count(old) != 1:
    sys.exit("Msg8: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
