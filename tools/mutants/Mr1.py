# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code
# a path here: a mutant that names one machine's worktree is the unresolvable
# `$S/mut.sh` that slice 003's record cites, in another file.
# Mr1 -- the annotatable set widened to admit `number`, which is the exact host mistake the
# README's new claim describes. Scores whether that claim's test is an anchor or a quotation.
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = '@annotatable_types ~w(string integer boolean)'
new = '@annotatable_types ~w(string integer boolean number object array)'
assert s.count(old) == 1
io.open(p, "w", encoding="utf-8").write(s.replace(old, new))
print("Mr1 applied")
