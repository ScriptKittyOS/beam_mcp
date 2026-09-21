# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/transport/http.ex, which passes the file to mutate as argv[1].
#
# Mss4 -- :server NOT THE PLUG'S: it rides into the module's new/1, which refuses an option it does not know.
import sys

p = sys.argv[1]
s = open(p).read()

old = '      :connection_timeout,\n      :server\n    ]'
new = '      :connection_timeout\n    ]'

if s.count(old) != 1:
    sys.exit("Mss4: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
