# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/canonical.ex, which passes the file to mutate as argv[1].
#
# Msg6 -- A SECOND SIGNER CALL SITE under lib/: signature/3 signs twice.
import sys

p = sys.argv[1]
s = open(p).read()

old = '  defp signer?(_), do: false\n'
new = '  defp signer?(_), do: false\n\n  @doc false\n  def sign_twice(signer, bytes, opts), do: {signer.sign(bytes, opts), signer.sign(bytes, opts)}\n'

if s.count(old) != 1:
    sys.exit("Msg6: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
