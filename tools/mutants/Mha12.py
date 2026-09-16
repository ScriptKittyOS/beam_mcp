# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code a path.
# Mha12 -- hash_value/2 no longer refuses a value naming a digest the option disagrees with
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = """      other ->
        raise ArgumentError,
              "the value names algorithm #{inspect(other)} and the option says #{inspect(algorithm)}"
"""
new = """      _other ->
        :ok"""
assert s.count(old) == 1, "anchor not found once: %d" % s.count(old)
s = s.replace(old, new)
io.open(p, "w", encoding="utf-8").write(s)
