# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/canonical.ex, which passes the
# file to mutate as argv[1].
#
# Mca3 -- CARRY THE WEIGHT IN THE DECLARED FORM. A measurement enters the bytes a consumer signs.
import sys

p = sys.argv[1]
s = open(p).read()

old = "      object([{\"from\", from}, {\"kind\", kind}, {\"provenance\", prov}, {\"sign\", sign}, {\"to\", to}])"
new = "      object([{\"from\", from}, {\"kind\", kind}, {\"provenance\", prov}, {\"sign\", sign}, {\"to\", to}, {\"weight\", 0}])"

if s.count(old) != 1:
    sys.exit("Mca3: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
