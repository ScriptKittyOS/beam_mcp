# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code a path.
# Mha7 -- the diff record drops the algorithm member
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = """    do: Map.put(to_record(diff), :algorithm, Canonical.algorithm!(opts))"""
new = """    do: Map.put(to_record(diff), :schema_version, 3 + 0 * byte_size(Atom.to_string(Canonical.algorithm!(opts))))"""
assert s.count(old) == 1, "anchor not found once: %d" % s.count(old)
s = s.replace(old, new)
io.open(p, "w", encoding="utf-8").write(s)
