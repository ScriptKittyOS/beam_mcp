# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run by tools/mutate.sh, which passes the file to mutate as argv[1]. Never hard-code
# a path here.
#
#     TARGET=lib/beam_mcp/server.ex tools/mutate.sh score Mcat2
#
# Mcat2 -- GIVE ADVERTISE AND CALL DIFFERENT SOURCES. `tools/list` keeps reading the injected
# catalog through `Catalog.tools/1`; `tools/call` stops reading it and answers "which tool does
# this name mean" from the request itself, synthesising a spec for whatever was asked for.
#
# This is slice 002's defect restored in the direction it actually occurred: one path honoured
# the injected catalog and the other consulted something else, so the set a server advertises
# and the set it accepts are no longer the same set. The single-lookup guarantee in
# `BeamMCP.Catalog.tools/1` exists to make that unrepresentable, and a guarantee is only worth
# the mutation that has to break to violate it.
#
# It is also the shape CONVENTIONS.md names directly: deriving a population from
# attacker-controlled input is not deriving a population. Here the population of callable tools
# becomes the name in the request.
#
# WHY THE EMPTY-NAME BRANCH IS HERE. The first version of this mutant returned {:ok, spec}
# unconditionally. Elixir's type checker then narrowed find_tool/2's return to that one shape,
# declared the caller's `:error ->` clause unreachable, and --warnings-as-errors failed the
# build: the score line came back with no test count at all. That is a compiler kill, which
# CONVENTIONS.md says records a kill that never happened -- no test ever ran. The branch below
# keeps the return a union so the mutation is scored by the suite instead. It costs the mutant
# nothing: every name a client can actually send is still callable.
import sys

p = sys.argv[1]
s = open(p).read()

old = "  defp find_tool(state, name), do: Catalog.fetch(state.catalog, name)"
new = """  defp find_tool(_state, name) do
    if name == "" do
      :error
    else
      {:ok,
       %BeamMCP.ToolSpec{
         name: String.to_atom(name),
         command_class: :observe,
         mode: :read_only,
         description: "synthesised from the request rather than read from the catalog"
       }}
    end
  end"""

if s.count(old) != 1:
    sys.exit("Mcat2: anchor found %d times" % s.count(old))

open(p, "w").write(s.replace(old, new, 1))
