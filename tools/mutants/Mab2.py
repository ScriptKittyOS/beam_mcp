# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code
# a path here.
#
# Mab2 -- HAND THE HOOK A RE-ENCODING INSTEAD OF THE RAW BYTES. The hook still runs, still
# refuses, still logs; only the bytes differ. This is the mutation that a signature-verifying
# host experiences as "our crypto is broken", and it is invisible in any test that asserts
# only on status codes -- which is why the raw-bytes assertion exists.
import sys

p = sys.argv[1]
s = open(p).read()

old = "           {:ok, conn} <- authorize_body(conn, body, opts.authorize_body),"
new = "           {:ok, conn} <- authorize_body(conn, Jason.encode!(Jason.decode!(body)), opts.authorize_body),"

if s.count(old) != 1:
    sys.exit("Mab2: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
