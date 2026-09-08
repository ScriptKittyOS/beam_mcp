# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code
# a path here: a mutant that names one machine's worktree is the unresolvable
# `$S/mut.sh` that slice 003's record cites, in another file.
# Me1, COMPLETED. Reverting header_values/2 alone leaves five :invalid_bytes clauses
# unreachable, and --warnings-as-errors rejects the build before the suite runs -- a compiler
# kill, which CONVENTIONS.md says records a kill that never happened. So the mutation removes
# what it orphans: the guard AND every clause that existed only to handle its sentinel.
import sys
p = sys.argv[1]
s = open(p).read()
subs = [
 ("""      case get_req_header(conn, name) do
        values -> if Enum.all?(values, &String.valid?/1), do: values, else: :invalid_bytes
      end""",
  """      get_req_header(conn, name)"""),
 ("""        :invalid_bytes ->
          {:refused, conn, 400, header_error(nil, "Origin header value is not valid UTF-8")}

""", ""),
 ("""          values == :invalid_bytes ->
            {:halt, param_error(id, name, "value is not valid UTF-8")}

""", ""),
 ("""        values == :invalid_bytes ->
          {:mismatch, 400, header_error(id, "#{header_name} header value is not valid UTF-8")}

""", ""),
 ("""        _ when values == :invalid_bytes ->
          {:mismatch, 400,
           header_error(id, "#{@protocol_header} header value is not valid UTF-8")}

""", ""),
]
for old, new in subs:
    if s.count(old) != 1:
        sys.exit("Me1: anchor %r found %d times" % (old[:40], s.count(old)))
    s = s.replace(old, new, 1)
open(p, "w").write(s)
