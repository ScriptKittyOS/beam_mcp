# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/edge.ex, which passes the file to mutate as argv[1].
#
# Mcn1 -- DEFAULT THE SIGN TO :allow. The one mutation the whole slice exists to refuse: the package writing a verdict. The sign census must see it, and every edge test that reads .sign must see it.
import sys

p = sys.argv[1]
s = open(p).read()

old = "defstruct [:from, :to, :kind, :provenance, :weight, sign: :unknown]"
new = "defstruct [:from, :to, :kind, :provenance, :weight, sign: :allow]"

if s.count(old) != 1:
    sys.exit("Mcn1: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
