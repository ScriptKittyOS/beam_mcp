# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code
# a path here: a mutant that names one machine's worktree is the unresolvable
# `$S/mut.sh` that slice 003's record cites, in another file.
#
#     TARGET=lib/beam_mcp/catalog.ex tools/mutate.sh score Mcat1
#
# Mcat1 -- DROP A REQUIRED KEY FROM THE SHAPE. `@required_keys` loses `:prompts`, so a host
# whose capabilities/0 omits it is accepted as well formed.
#
# This is the mutation the whole slice is about. The reason `resources` and `prompts` are
# required-and-may-be-empty is that an absent key and an empty one are different claims: absent
# means the host never wrote the key, empty means it wrote it and has none. Relaxing the check
# by one key makes the two indistinguishable again, and the only place that difference is
# visible is startup -- by the first request the map has already been read.
#
# It is deliberately the smallest possible relaxation: one key out of three, no message change,
# no behaviour change for a correct host. A checker that only rejects the malformed catalogs
# nobody writes is not a checker.
import sys

p = sys.argv[1]
s = open(p).read()

old = "  @required_keys [:tools, :resources, :prompts]"
new = "  @required_keys [:tools, :resources]"

if s.count(old) != 1:
    sys.exit("Mcat1: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
