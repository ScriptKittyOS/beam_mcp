# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code
# a path here: a mutant that names one machine's worktree is the unresolvable
# `$S/mut.sh` that slice 003's record cites, in another file.
# Mr2 -- collision detection defeated: the uniqueness check groups by the ORIGINAL name rather
# than the case-folded one, so `Dup` and `DUP` no longer collide. This is the (b) defect
# reintroduced in the shape that looks most like a tidy-up.
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = "        |> Enum.group_by(fn {name, _path, _type} -> String.downcase(name) end)"
new = "        |> Enum.group_by(fn {name, _path, _type} -> name end)"
assert s.count(old) == 1, s.count(old)
io.open(p, "w", encoding="utf-8").write(s.replace(old, new))
print("Mr2 applied")
