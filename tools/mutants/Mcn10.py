# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/node.ex, which passes the file
# to mutate as argv[1].
#
# Mcn10 -- DROP THE `/` ESCAPE, KEEP THE `%` ONE. The swap mutant (Mcn9) dies on "a/b" versus
# "a%2Fb"; this one does not, because "a/b" still escapes nothing that "a%2Fb" collides with.
# What collides instead is the boundary between components: {:tool, "srv/tool", "x"} and
# {:tool, "srv", "tool/x"} both join to "srv/tool/tool/x". A review lane found the first
# four anchors silent on it.
import sys

p = sys.argv[1]
s = open(p).read()

old = '    component |> String.replace("%", "%25") |> String.replace("/", "%2F")'
new = '    component |> String.replace("%", "%25")'

if s.count(old) != 1:
    sys.exit("Mcn10: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
