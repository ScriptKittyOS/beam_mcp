# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code a path.
# Mha1 -- the algorithm is not written into the bytes: the member is always sha256 whatever the option
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = """         ~s(,"algorithm":"),
         Atom.to_string(algorithm),"""
new = """         ~s(,"algorithm":"),
         Atom.to_string(algorithm) |> then(fn _ -> "sha256" end),"""
assert s.count(old) == 1, "anchor not found once: %d" % s.count(old)
s = s.replace(old, new)
io.open(p, "w", encoding="utf-8").write(s)
