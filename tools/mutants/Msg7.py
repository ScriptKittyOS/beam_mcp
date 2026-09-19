# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/canonical.ex, which passes the file to mutate as argv[1].
#
# Msg7 -- THE HOST'S OPTIONS DO NOT REACH THE SIGNER: signature/3 hands it [].
import sys

p = sys.argv[1]
s = open(p).read()

old = '      case signer.sign(bytes, opts) do'
new = '      case signer.sign(bytes, opts -- opts) do'

if s.count(old) != 1:
    sys.exit("Msg7: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
