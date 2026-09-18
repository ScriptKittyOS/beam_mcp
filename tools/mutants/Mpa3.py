# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=test/support/public_api.ex, which passes the file to
# mutate as argv[1]. The public-API census's population and grammar live there.
#
# Mpa3 -- HIDDEN DOCS ARE PUBLIC: a @doc false entry joins the population, so a docs-hidden flip is no change at all.
import sys

p = sys.argv[1]
s = open(p).read()

old = '        kind in @kinds,\n        doc != :hidden,\n        meta = if(is_map(meta), do: meta, else: %{}),'
new = '        kind in @kinds,\n        doc != :never,\n        meta = if(is_map(meta), do: meta, else: %{}),'

if s.count(old) != 1:
    sys.exit("Mpa3: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
