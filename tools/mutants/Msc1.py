# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/canonical.ex, which passes the file to mutate as argv[1].
#
# Msc1 -- THE COPY-THROUGH DROPPED: scheme: is always nil, whatever the host asserted.
import sys

p = sys.argv[1]
s = open(p).read()

old = '             scheme: Keyword.get(opts, :scheme),'
new = '             scheme: nil,'

if s.count(old) != 1:
    sys.exit("Msc1: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
