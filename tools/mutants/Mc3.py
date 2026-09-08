# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code
# a path here: a mutant that names one machine's worktree is the unresolvable
# `$S/mut.sh` that slice 003's record cites, in another file.
# Mc3 -- mirrored_params/2 stops recognising the host-fault sentinel, so a raising or
# malformed host catalog collapses to "this tool mirrors nothing" and header checking is
# silently disabled. This is round 5's M8 re-scored on the tree that ships.
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = "        {__MODULE__, :host_fault, _k, _r, _st} = fault -> fault\n"
assert s.count(old) == 1
io.open(p, "w", encoding="utf-8").write(s.replace(old, ""))
print("Mc3 applied")
