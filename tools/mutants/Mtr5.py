# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/tracer.ex, which passes the
# file to mutate as argv[1].
#
# Mtr5 -- A SECOND TRACER IS ADMITTED: already_started is answered with the running pid as if it were new.
import sys

p = sys.argv[1]
s = open(p).read()

old = "        {:error, {:already_started, _}} -> {:error, :already_running}"
new = "        {:error, {:already_started, pid}} -> {:ok, pid}"

if s.count(old) != 1:
    sys.exit("Mtr5: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
