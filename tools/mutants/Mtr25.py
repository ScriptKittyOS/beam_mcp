# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/tracer.ex, which passes the
# file to mutate as argv[1].
#
# Mtr25 -- stop/0 FINDS NO CLAIM: the tracer's own claim is never read, so nothing is raised or destroyed first and the stop is queue-ordered.
import sys

p = sys.argv[1]
s = open(p).read()

old = '    with {{:dictionary, @claim}, {flag, _session} = claim} <-'
new = '    with {{:dictionary, @claim}, {flag, _session, :never} = claim} <-'

if s.count(old) != 1:
    sys.exit("Mtr25: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
