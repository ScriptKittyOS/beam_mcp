# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/canonical.ex, which passes the file to mutate as argv[1].
#
# Msc2 -- key_id: NOT COPIED: the host's key id is lost between the signer and the result.
import sys

p = sys.argv[1]
s = open(p).read()

old = '             key_id: Keyword.get(opts, :key_id)'
new = '             key_id: nil'

if s.count(old) != 1:
    sys.exit("Msc2: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
