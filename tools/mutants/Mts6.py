# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/tracer.ex, which passes the
# file to mutate as argv[1].
#
# Mts6 -- A CRAFTED SESSION IN A CLAIM RAISES OUT OF stop/0: session_destroy/1 on a term that is no handle is not rescued.
import sys

p = sys.argv[1]
s = open(p).read()

old = '  defp destroy(session) do\n    :trace.session_destroy(session)\n  rescue\n    ArgumentError -> false\n  end'
new = '  defp destroy(session) do\n    :trace.session_destroy(session)\n  end'

if s.count(old) != 1:
    sys.exit("Mts6: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
