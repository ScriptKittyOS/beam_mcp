# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/reach.ex, which passes the
# file to mutate as argv[1].
#
# Mrc8 -- PATH COMPRESSION KEEPS THE WRONG LABEL: the comparison is reversed.
import sys

p = sys.argv[1]
s = open(p).read()

old = '        if st.semi[st.label[a]] < st.semi[st.label[v]],\n'
new = '        if st.semi[st.label[a]] > st.semi[st.label[v]],\n'

if s.count(old) != 1:
    sys.exit("Mrc8: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
