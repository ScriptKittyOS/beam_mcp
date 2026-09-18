# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=test/support/public_api.ex, which passes the file to
# mutate as argv[1]. The public-API census's population, grammar and rule live there.
#
# Mpa20 -- ON 1.x A PATCH MAY ADD AND DEPRECATE: the release step lets a 1.x patch write since=/deprecated_since= (a lane's LOW-3).
import sys

p = sys.argv[1]
s = open(p).read()

old = '  defp refusal(%{major: major, patch: patch}, _removal?, true) when major >= 1 and patch != 0,'
new = '  defp refusal(%{major: major, patch: patch}, _removal?, true) when major >= 1 and patch != 0 and patch < 0,'

if s.count(old) != 1:
    sys.exit("Mpa20: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
