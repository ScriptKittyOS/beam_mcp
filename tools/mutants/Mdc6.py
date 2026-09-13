# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/declared.ex, which passes the
# file to mutate as argv[1].
#
# Mdc6 -- IGNORE THE ALLOWLIST. Every dynamic site stays unresolved whatever the host vouched for.
import sys

p = sys.argv[1]
s = open(p).read()

old = "        Enum.split_with(unresolved, fn {caller, _} ->\n          caller in allowlist\n        end)"
new = "        Enum.split_with(unresolved, fn {caller, _} ->\n          _ = {caller, allowlist}\n          false\n        end)"

if s.count(old) != 1:
    sys.exit("Mdc6: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
