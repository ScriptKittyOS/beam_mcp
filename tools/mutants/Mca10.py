# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/canonical.ex, which passes the
# file to mutate as argv[1].
#
# Mca10 -- ATOM KEY NOT NORMALISED. An atom label key is written as spelled, so a combining sequence stays NFD.
import sys

p = sys.argv[1]
s = open(p).read()

old = "    do: {:ok, nfc(Atom.to_string(k))}"
new = "    do: {:ok, Atom.to_string(k)}"

if s.count(old) != 1:
    sys.exit("Mca10: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
