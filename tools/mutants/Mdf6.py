# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/diff.ex, which passes the
# file to mutate as argv[1].
#
# Mdf6 -- A MISSING WINDOW IS INFERRED AS EMPTY instead of refused by name.
import sys

p = sys.argv[1]
s = open(p).read()

old = "      :error ->\n        {:error, {:missing, :window}}"
new = "      :error ->\n        {:ok, %{}}"

if s.count(old) != 1:
    sys.exit("Mdf6: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
