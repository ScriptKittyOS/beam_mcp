# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/signer.ex, which passes the file to mutate as argv[1].
#
# Msg2 -- THE FIRST ARGUMENT IS RENAMED: `bytes` for `canonical_bytes` -- the name that says what is signed.
import sys

p = sys.argv[1]
s = open(p).read()

old = '  @callback sign(canonical_bytes :: binary(), opts :: keyword()) ::'
new = '  @callback sign(bytes :: binary(), opts :: keyword()) ::'

if s.count(old) != 1:
    sys.exit("Msg2: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
