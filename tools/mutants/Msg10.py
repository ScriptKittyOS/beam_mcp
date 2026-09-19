# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/canonical.ex, which passes the file to mutate as argv[1].
#
# Msg10 -- ANY ATOM IS A SIGNER: the loaded-module-with-sign/2 check becomes true, and a non-signer raises UndefinedFunctionError out of signature/3.
import sys

p = sys.argv[1]
s = open(p).read()

old = '    do: Code.ensure_loaded?(signer) and function_exported?(signer, :sign, 2)\n'
new = '    do: true\n'

if s.count(old) != 1:
    sys.exit("Msg10: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
