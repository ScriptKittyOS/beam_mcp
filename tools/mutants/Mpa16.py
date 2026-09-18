# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=test/support/public_api.ex, which passes the file to
# mutate as argv[1]. The public-API census's population, grammar and rule live there.
#
# Mpa16 -- THE RELEASE STEP LETS A REMOVAL SHIP IN A 1.x MINOR: the major rule is dropped (a lane's LOW, held by the one command that knows the number).
import sys

p = sys.argv[1]
s = open(p).read()

old = '  defp refusal(%{major: major, minor: minor}, true, _any?) when major >= 1 and minor != 0,'
new = '  defp refusal(%{major: major, minor: minor}, true, _any?) when major >= 1 and minor != 0 and minor < 0,'

if s.count(old) != 1:
    sys.exit("Mpa16: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
