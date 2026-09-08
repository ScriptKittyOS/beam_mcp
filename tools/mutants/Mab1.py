# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code
# a path here: a mutant that names one machine's worktree is the unresolvable
# `$S/mut.sh` that slice 003's record cites, in another file.
#
# Mab1 -- REMOVE THE HOOK ENTIRELY. Deletes the authorize_body/3 call from handle/2, so a
# configured hook is never consulted and every request is served as though it had passed.
#
# COMPLETE, not partial: dropping only the call leaves authorize_body/3 defined and unused,
# and --warnings-as-errors would reject the build before a test ran -- a compiler kill, which
# CONVENTIONS.md says records a kill that never happened. So the clauses go too.
import sys

p = sys.argv[1]
s = open(p).read()

subs = [
    # the call site
    ("""           {:ok, conn} <- authorize_body(conn, body, opts.authorize_body),\n""", ""),
    # the nil clause
    ("""    defp authorize_body(conn, _body, nil), do: {:ok, conn}\n\n""", ""),
]

for old, new in subs:
    if s.count(old) != 1:
        sys.exit("Mab1: anchor %r found %d times" % (old[:48], s.count(old)))
    s = s.replace(old, new, 1)

# the implementing clause, from its head to the start of the next function
start = s.index("    defp authorize_body(conn, body, authorize_body_fun) do")
end = s.index("    defp check_origin(conn, :any), do: {:ok, conn}")
s = s[:start] + s[end:]

open(p, "w").write(s)
