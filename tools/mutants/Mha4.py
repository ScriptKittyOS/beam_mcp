# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code a path.
# Mha4 -- an unknown name is admitted: the option list is wider than the page
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = """  @algorithms [:sha256, :sha384, :sha512]"""
new = """  @algorithms [:sha256, :sha384, :sha512, :md5]"""
assert s.count(old) == 1, "anchor not found once: %d" % s.count(old)
s = s.replace(old, new)
io.open(p, "w", encoding="utf-8").write(s)
