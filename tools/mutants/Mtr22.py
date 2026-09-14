# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/tracer.ex, which passes the
# file to mutate as argv[1].
#
# Mtr22 -- THE FLAG IN THE RUNNING TERM IS TRUSTED UNCHECKED: stop/0 raises on a forged one after clearing, with the tracer left alive.
import sys

p = sys.argv[1]
s = open(p).read()

old = "      {flag, modules, _companion} = term when is_reference(flag) ->"
new = "      {flag, modules, _companion} = term when is_reference(flag) or is_atom(flag) ->"

if s.count(old) != 1:
    sys.exit("Mtr22: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
