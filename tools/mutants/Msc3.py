# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/canonical.ex, which passes the file to mutate as argv[1].
#
# Msc3 -- :scheme READ INTO THE ENCODE: the encode refuses an option it does not know, so a scheme-carrying call fails where the bytes should not have moved.
import sys

p = sys.argv[1]
s = open(p).read()

old = '    {encode_opts, _} = Keyword.split(opts, [:algorithm])'
new = '    {encode_opts, _} = Keyword.split(opts, [:algorithm, :scheme])'

if s.count(old) != 1:
    sys.exit("Msc3: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
