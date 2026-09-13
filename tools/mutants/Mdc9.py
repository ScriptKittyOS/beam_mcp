# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/declared.ex, which passes the
# file to mutate as argv[1].
#
# Mdc9 -- BUILD AN UNKNOWN APP AS EMPTY. The typo case review found: a valid, empty connectome for an application no .app describes.
import sys

p = sys.argv[1]
s = open(p).read()

old = "          {:halt, {:error, {:unknown_app, app}}}"
new = "          {:cont, {:ok, acc}}"

if s.count(old) != 1:
    sys.exit("Mdc9: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
