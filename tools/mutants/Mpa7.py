# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=test/support/public_api.ex, which passes the file to
# mutate as argv[1]. The public-API census's population and grammar live there.
#
# Mpa7 -- ADDITIONS ARE NOT MARKED: a new entry is written without since=, so no CHANGELOG line is ever asked for it.
import sys

p = sys.argv[1]
s = open(p).read()

old = '         |> Map.merge(if(initial, do: %{}, else: %{"since" => @unreleased}))}'
new = '         |> Map.merge(if(initial or not initial, do: %{}, else: %{"since" => @unreleased}))}'

if s.count(old) != 1:
    sys.exit("Mpa7: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
