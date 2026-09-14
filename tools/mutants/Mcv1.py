# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/canonical.ex, which passes the
# file to mutate as argv[1].
#
# Mcv1 -- A NON-MAP RECORD IS WRITTEN AS ITS INSPECTION, not refused by name.
import sys

p = sys.argv[1]
s = open(p).read()

old = "  def encode_value(value, field),\n    do: {:error, {:uncanonical, {:label_value, \"record\", field, value}}}"
new = "  def encode_value(value, field),\n    do: {:ok, inspect({field, value})}"
if s.count(old) != 1:
    sys.exit("Mcv1: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
