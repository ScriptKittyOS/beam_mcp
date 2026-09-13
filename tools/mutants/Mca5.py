# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/canonical.ex, which passes the
# file to mutate as argv[1].
#
# Mca5 -- SKIP NFC. A combining sequence and its precomposed form encode differently, and two ids that coincide after NFC are no longer refused.
import sys

p = sys.argv[1]
s = open(p).read()

old = "  defp nfc(s), do: String.normalize(s, :nfc)"
new = "  defp nfc(s), do: s"

if s.count(old) != 1:
    sys.exit("Mca5: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
