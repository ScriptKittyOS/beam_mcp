# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code a path.
# Mjs33 -- the citation reader keeps ExUnit's describe prefix, so a cited bare name is never live in a describe
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = """      |> String.replace_prefix(describe_prefix(tags), "")"""
new = """      |> String.replace_prefix(describe_prefix(tags) <> "?", "")"""
assert s.count(old) == 1, "anchor not found once: %d" % s.count(old)
s = s.replace(old, new)
io.open(p, "w", encoding="utf-8").write(s)
