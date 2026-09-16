# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code a path.
# Mha9 -- the diff hashes with the default whatever the option, over bytes that name the option
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = """    Canonical.hash_value(with_algorithm(diff, algorithm: algorithm), algorithm: algorithm)
  end"""
new = """    Canonical.hash_value(with_algorithm(diff, algorithm: algorithm))
  end"""
assert s.count(old) == 1, "anchor not found once: %d" % s.count(old)
s = s.replace(old, new)
io.open(p, "w", encoding="utf-8").write(s)
