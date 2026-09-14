# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/diff.ex, which passes the
# file to mutate as argv[1].
#
# Mdf14 -- AN UNKNOWN OPTION IS ACCEPTED SILENTLY: a typo in `window:` reads as no window.
import sys

p = sys.argv[1]
s = open(p).read()

old = "      (unknown = Keyword.keys(opts) -- @options) != [] -> {:error, {:invalid, :opts, unknown}}"
new = "      (unknown = Keyword.keys(opts) -- @options) == [:never] -> {:error, {:invalid, :opts, unknown}}"

if s.count(old) != 1:
    sys.exit("Mdf14: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
