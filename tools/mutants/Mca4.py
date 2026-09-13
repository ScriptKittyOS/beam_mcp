# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/canonical.ex, which passes the
# file to mutate as argv[1].
#
# Mca4 -- DROP THE SIGN FROM THE DECLARED FORM. A host`s :deny would not be in what it signs.
import sys

p = sys.argv[1]
s = open(p).read()

old = "      object([{\"from\", from}, {\"kind\", kind}, {\"provenance\", prov}, {\"sign\", sign}, {\"to\", to}])"
new = "      _ = sign\n      object([{\"from\", from}, {\"kind\", kind}, {\"provenance\", prov}, {\"to\", to}])"

if s.count(old) != 1:
    sys.exit("Mca4: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
