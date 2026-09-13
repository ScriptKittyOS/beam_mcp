# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/canonical.ex, which passes the
# file to mutate as argv[1].
#
# Mca12 -- ACCEPT INVALID UTF-8. The validity check always passes, so a bad byte reaches the writer.
import sys

p = sys.argv[1]
s = open(p).read()

old = "    if String.valid?(s), do: {:ok, s}, else: {:error, {:uncanonical, {:invalid_utf8, id, field}}}"
new = "    if true, do: {:ok, s}, else: {:error, {:uncanonical, {:invalid_utf8, id, field}}}"

if s.count(old) != 1:
    sys.exit("Mca12: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
