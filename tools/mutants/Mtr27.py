# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/tracer.ex, which passes the
# file to mutate as argv[1].
#
# Mtr27 -- A CLAIM IS TRUSTED ON EITHER CHECK: a squatter's crafted module list is cleared and raises out of stop/0, or a crafted flag clears a host's pattern.
import sys

p = sys.argv[1]
s = open(p).read()

old = "         true <- is_reference(flag) and atoms?(modules) do"
new = "         true <- is_reference(flag) or atoms?(modules) do"

if s.count(old) != 1:
    sys.exit("Mtr27: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
