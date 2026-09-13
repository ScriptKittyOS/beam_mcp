# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/canonical.ex, which passes the
# file to mutate as argv[1].
#
# Mca16 -- A REFUSAL INSIDE A LIST NAMES THE ELEMENT, NOT THE LABEL AND ITS WHOLE VALUE. The inner error passes through unwrapped.
import sys

p = sys.argv[1]
s = open(p).read()

old = "      {:ok, items} -> {:ok, {:array, items}}\n      {:error, _} -> {:error, {:uncanonical, {:label_value, id, k, v}}}\n"
new = "      {:ok, items} -> {:ok, {:array, items}}\n      {:error, _} = e -> e\n"

if s.count(old) != 1:
    sys.exit("Mca16: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
