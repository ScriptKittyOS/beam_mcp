# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/tracer.ex, which passes the
# file to mutate as argv[1].
#
# Mtr14 -- A FAILED START LEAVES ITS PATTERNS: the rescue clears nothing.
import sys

p = sys.argv[1]
s = open(p).read()

old = "      e ->\n        clear(modules)\n        send(companion, :cancel)\n        reraise e, __STACKTRACE__"
new = "      e ->\n        send(companion, :cancel)\n        reraise e, __STACKTRACE__"

if s.count(old) != 1:
    sys.exit("Mtr14: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
