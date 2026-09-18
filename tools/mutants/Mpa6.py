# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=test/support/public_api.ex, which passes the file to
# mutate as argv[1]. The public-API census's population and grammar live there.
#
# Mpa6 -- THE WRITER DROPS LINES THAT ARE NO LONGER PUBLIC: the record of a removal vanishes on the next write.
import sys

p = sys.argv[1]
s = open(p).read()

old = '    existing = if File.exists?(path), do: Map.new(read_baseline!(path)), else: %{}'
new = '    existing =\n      if File.exists?(path),\n        do: Map.new(Enum.filter(read_baseline!(path), fn {e, _} -> e in population() end)),\n        else: %{}'

if s.count(old) != 1:
    sys.exit("Mpa6: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
