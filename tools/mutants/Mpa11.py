# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=test/support/public_api.ex, which passes the file to
# mutate as argv[1]. The public-API census's population, grammar and rule live there.
#
# Mpa11 -- A HIDDEN MODULE IS PUBLIC: @moduledoc false modules enter the population (a lane's Mb2).
import sys

p = sys.argv[1]
s = open(p).read()

old = '        {:docs_v1, _, _, _, mdoc, _, entries} <- [Code.fetch_docs(m)],\n        mdoc != :hidden,'
new = '        {:docs_v1, _, _, _, mdoc, _, entries} <- [Code.fetch_docs(m)],\n        mdoc != :never,'

if s.count(old) != 1:
    sys.exit("Mpa11: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
