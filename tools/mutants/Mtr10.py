# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/tracer.ex, which passes the
# file to mutate as argv[1].
#
# Mtr10 -- NO EARLY CLEAR: only handled messages count against the limit; what is queued keeps arriving until the limit-th write.
import sys

p = sys.argv[1]
s = open(p).read()

old = "      _ when seen + queued >= max ->"
new = "      _ when seen + queued * 0 >= max ->"

if s.count(old) != 1:
    sys.exit("Mtr10: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
