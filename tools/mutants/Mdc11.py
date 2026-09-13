# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/declared.ex, which passes the
# file to mutate as argv[1].
#
# Mdc11 -- READ THE CATALOG WITHOUT THE CONTRACT CHECK. A catalog the package refuses is read anyway, and a tools entry that is not a ToolSpec is skipped in silence.
import sys

p = sys.argv[1]
s = open(p).read()

old = "          :ok -> read_catalog(module, server)\n          {:error, reason} -> {:error, {:invalid, :catalog, reason}}"
new = "          :ok -> read_catalog(module, server)\n          {:error, _reason} -> read_catalog(module, server)"

if s.count(old) != 1:
    sys.exit("Mdc11: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
