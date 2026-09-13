# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh with TARGET=lib/beam_mcp/connectome/node.ex, which passes the file to mutate as argv[1].
#
# Mcn6 -- A SECOND ID SITE. A public id/1 clause that formats a tool identity its own way, taking precedence for that shape. The single-site census must catch it by count; the id tests may too.
import sys

p = sys.argv[1]
s = open(p).read()

old = "  def id(identity) do\n    identity |> id_parts() |> Enum.map_join(\"/\", &escape/1)\n  end"
new = "  def id({:tool, server, name}) when is_binary(server), do: server <> \":\" <> to_string(name)\n\n  def id(identity) do\n    identity |> id_parts() |> Enum.map_join(\"/\", &escape/1)\n  end"

if s.count(old) != 1:
    sys.exit("Mcn6: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
