# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/diff.ex, which passes the
# file to mutate as argv[1].
#
# Mdf13 -- THE KIND IS NOT PART OF THE LABEL: a->b under two kinds is one edge, and an edge
# and a label stop being the same count. A review lane ran this mutant in a scratchpad and
# every test passed; the kind test and the property's kinds are what kill it now.
import sys

p = sys.argv[1]
s = open(p).read()

old = "      {{nfc(from), nfc(to), kind}, sign}"
new = "      {{nfc(from), nfc(to), kind && :invoke}, sign}"

if s.count(old) != 1:
    sys.exit("Mdf13: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
