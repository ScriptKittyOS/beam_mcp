# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/observed.ex, which passes the
# file to mutate as argv[1].
#
# Mob4 -- THE HANDLER STAYS ATTACHED after the collector stops; the next call fails against a missing table.
import sys

p = sys.argv[1]
s = open(p).read()

old = "    :telemetry.detach({__MODULE__, name})"
new = "    _ = {__MODULE__, name}"

if s.count(old) != 1:
    sys.exit("Mob4: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
