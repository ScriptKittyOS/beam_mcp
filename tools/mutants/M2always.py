# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code
# a path here: a mutant that names one machine's worktree is the unresolvable
# `$S/mut.sh` that slice 003's record cites, in another file.
# M2always -- fault_response/4 ALWAYS re-raises. Serves a bodyless 500 through the adapter,
# which is the failure this module exists to avoid.
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = """    defp fault_response(conn, exception, stacktrace, id) do
      if Plug.Exception.status(exception) == 500 do
        Logger.error(Exception.format(:error, exception, stacktrace))
        send_json(conn, 500, error(id, -32_603, "Internal error"))
      else
        reraise exception, stacktrace
      end
    end"""
new = """    defp fault_response(_conn, exception, stacktrace, _id) do
      reraise exception, stacktrace
    end"""
assert s.count(old) == 1, "anchor not found once: %d" % s.count(old)
io.open(p, "w", encoding="utf-8").write(s.replace(old, new))
print("M2always applied")
