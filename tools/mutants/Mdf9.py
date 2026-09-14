# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/diff.ex, which passes the
# file to mutate as argv[1].
#
# Mdf9 -- LABELS ARE COMPARED BEFORE NFC: one label in two classes, and bytes a page-only consumer cannot reproduce.
import sys

p = sys.argv[1]
s = open(p).read()

old = "      {{nfc(from), nfc(to), kind}, sign}"
new = "      {{from, to, kind}, sign}"

if s.count(old) != 1:
    sys.exit("Mdf9: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
