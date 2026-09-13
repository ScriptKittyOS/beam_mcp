# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/canonical.ex, which passes the
# file to mutate as argv[1].
#
# Mca18 -- EDGE KEY ORDERED (from, kind, to, provenance). Two edges from one node sort by
# kind before to; every object written is unchanged, so only the order between such edges
# can tell. Every reader of the tuple is re-spelled with it: the JSON writer, the two
# exporters' comprehensions (one anchor, two sites) and the sidecar's element reads.
import sys

p = sys.argv[1]
s = open(p).read()

edits = [
    ("     {{nfc(e.from), nfc(e.to), Atom.to_string(e.kind), Atom.to_string(e.provenance)},",
     "     {{nfc(e.from), Atom.to_string(e.kind), nfc(e.to), Atom.to_string(e.provenance)},", 1),
    ("  defp json({{from, to, kind, prov}, sign}) do",
     "  defp json({{from, kind, to, prov}, sign}) do", 1),
    ("        for {{from, to, kind, prov}, sign} <- edges do",
     "        for {{from, kind, to, prov}, sign} <- edges do", 2),
    ('             {"kind", elem(key, 2)},', '             {"kind", elem(key, 1)},', 1),
    ('             {"to", elem(key, 1)},', '             {"to", elem(key, 2)},', 1),
]

for old, new, n in edits:
    if s.count(old) != n:
        sys.exit("Mca18: anchor found %d times, wanted %d: %s" % (s.count(old), n, old))
    s = s.replace(old, new)

open(p, "w").write(s)
