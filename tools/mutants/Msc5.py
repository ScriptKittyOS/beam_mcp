# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/canonical.ex, which passes the file to mutate as argv[1].
#
# Msc5 -- THE VOCABULARY WIDENED BY ONE NAME without a row on the page.
import sys

p = sys.argv[1]
s = open(p).read()

old = '  @type scheme :: :ed25519 | :ecdsa_p384_sha384 | :mldsa87'
new = '  @type scheme :: :ed25519 | :ecdsa_p384_sha384 | :mldsa87 | :rsa_pss_sha256'

if s.count(old) != 1:
    sys.exit("Msc5: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
