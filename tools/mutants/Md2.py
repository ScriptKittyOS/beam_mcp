# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code
# a path here: a mutant that names one machine's worktree is the unresolvable
# `$S/mut.sh` that slice 003's record cites, in another file.
# Md2 -- CLOSES ALWAYS: every refusal gets `connection: close`, not only the ones in front of
# the body read. A fix that cannot tell the two sides of the split apart is not the fix.
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = """      case result do
        {:refused, conn, status, payload} -> {:refused, close_after(conn), status, payload}
        ok -> ok
      end
    end"""
new = """      result
    end"""
assert s.count(old) == 1
s = s.replace(old, new)
old2 = "        {:refused, conn, status, payload} -> send_json(conn, status, payload)"
new2 = "        {:refused, conn, status, payload} -> send_json(close_after(conn), status, payload)"
assert s.count(old2) == 1, "handle/2 else not found once: %d" % s.count(old2)
s = s.replace(old2, new2)
io.open(p, "w", encoding="utf-8").write(s)
print("Md2 applied")
