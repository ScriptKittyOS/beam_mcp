# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/node.ex, which passes the file to mutate as argv[1].
#
# Mcn7 -- INFER THE LEVEL FROM THE KIND. A node of kind :tool is silently given level :server whatever the caller said. The field-named constraint: one field must never be derived from the other.
import sys

p = sys.argv[1]
s = open(p).read()

old = "      {:ok, %__MODULE__{id: id, kind: kind, level: level, labels: labels}}"
new = "      level = if kind in [:tool, :resource, :prompt, :process], do: :server, else: level\n      {:ok, %__MODULE__{id: id, kind: kind, level: level, labels: labels}}"

if s.count(old) != 1:
    sys.exit("Mcn7: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
