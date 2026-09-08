# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code
# a path here: a mutant that names one machine's worktree is the unresolvable
# `$S/mut.sh` that slice 003's record cites, in another file.
# Md1 -- the (d) fix removed: a pre-read refusal goes out without `connection: close`.
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
assert s.count(old) == 1, "anchor not found once: %d" % s.count(old)
s = s.replace(old, new)
# close_after/1 is now unused: remove it, or --warnings-as-errors fails the build before the
# suite runs and the table records a kill no test made.
start = s.index("    # Refusing before the body is read leaves the connection")
end = s.index('defp close_after(conn), do: put_resp_header(conn, "connection", "close")\n', start)
end += len('defp close_after(conn), do: put_resp_header(conn, "connection", "close")\n')
s = s[:start] + s[end:]
assert "close_after(conn)" not in s, "orphan call left behind"
io.open(p, "w", encoding="utf-8").write(s)
print("Md1 applied")
