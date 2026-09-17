# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code a path.
# Mof4 -- the message drops the reason, leaving only a number
import io
import sys
p = sys.argv[1]
s = io.open(p, encoding="utf-8").read()
old = """        OTP 26.2 added the keyed process_info read the connectome tracer depends on --"""
new = """        The tracer needs a newer OTP --"""
assert s.count(old) == 1, "anchor not found once: %d" % s.count(old)
s = s.replace(old, new)
io.open(p, "w", encoding="utf-8").write(s)
