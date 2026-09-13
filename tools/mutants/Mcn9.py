# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/node.ex, which passes the file
# to mutate as argv[1].
#
# Mcn9 -- SWAP THE TWO ESCAPES. Escaping `/` before `%` turns "a/b" into "a%2Fb" and then
# into "a%252Fb" -- the same string "a%2Fb" itself escapes to. Two identities, one id. The
# injectivity claim in the moduledoc is only as true as this order, and a review lane found
# nothing pinning it.
import sys

p = sys.argv[1]
s = open(p).read()

old = '    component |> String.replace("%", "%25") |> String.replace("/", "%2F")'
new = '    component |> String.replace("/", "%2F") |> String.replace("%", "%25")'

if s.count(old) != 1:
    sys.exit("Mcn9: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
