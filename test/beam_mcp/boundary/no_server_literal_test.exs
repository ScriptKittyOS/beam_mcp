# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Boundary.NoServerLiteralTest do
  # boundary: the transports reach the core through the `:server` option, never by name
  #
  # `BeamMCP.Transport.HTTP.init/1` and `BeamMCP.Transport.Stdio.run/1` take `:server`, a module,
  # default `BeamMCP.Server`, and call `new/1`, `handle_message/2` and (stdio, whose loop must
  # know when it ends) `shutdown?/1` through it. That is what lets a host put a wrapper above
  # the core -- the composed system's approval-shaped `input_required` lives there, not here
  # (will-not-implement entry 12 is unchanged: the core answers completely). The seam holds
  # only if no call site names the core: a literal `Server.new` beside `opts.server.new`
  # would serve the default whatever the host passed. Three readings, each over the whole of
  # lib/ with no path or module listed -- a review lane planted a transport at
  # lib/beam_mcp/transports/leak.ex with two literal calls and a version of this file that
  # filtered by "lib/beam_mcp/transport/" passed it: (1) the text, where the only call of
  # `Server.` by name is the core's own moduledoc example; (2) the artefact's call edges, where
  # no lib/ module but `BeamMCP.Server` itself calls a function of it -- an alias under another
  # name, `apply/3` with a literal module, a module attribute all resolve to that edge; and
  # (3) the artefact's atom sites, where `BeamMCP.Server` appears in a module's compiled forms
  # exactly once per transport, as the default value -- the reading that catches the spelling
  # the other two miss (`Server |> then(& &1.new(x))` compiles to a variable-module call, the
  # same unresolved edge as `opts.server.new(x)`, with the atom at a second site; the lane
  # measured both pins green under it). The alias compiles to nothing and doc strings are not
  # in the forms, so a site is a site.
  use ExUnit.Case, async: true
  alias BeamMCP.Boundary

  @core_file "lib/beam_mcp/server.ex"
  @default ~r/Keyword\.(get|pop)\(opts, :server, Server\)/
  @alias ~r/^\s*alias BeamMCP\.Server$/

  test "no line under lib/ calls BeamMCP.Server by name, but the core's own moduledoc example" do
    # A call is the module, a dot, a function name and an opening parenthesis; a doc line's
    # `BeamMCP.Server.new/1` is a reference, not a call, and `GenServer.stop(` has no word
    # boundary before `Server`. The one hit is the example in BeamMCP.Server's moduledoc.
    hits =
      for {path, _, _} = hit <- Boundary.hits(~r/\bServer\.\w+[!?]?\(/),
          path != @core_file,
          do: hit

    assert hits == [], "BeamMCP.Server called by name under lib/:\n  " <> Boundary.format(hits)
    assert [{@core_file, _, _}] = Boundary.hits(~r/\bServer\.\w+[!?]?\(/)
  end

  test "from the artefact: no module under lib/ but BeamMCP.Server itself calls a function of it" do
    {edges, _unresolved} = Boundary.xref()

    calls =
      for {{m, _, _} = from, {BeamMCP.Server, f, a}} <- edges,
          m != BeamMCP.Server,
          do: {from, f, a}

    assert calls == [],
           "edges into BeamMCP.Server from another module:\n  " <>
             Enum.map_join(calls, "\n  ", &inspect/1)
  end

  test "from the artefact: BeamMCP.Server appears in another module's compiled forms exactly once per transport, as the default value" do
    # Every site of the atom outside its own module -- generated ones included: an `if`'s
    # clauses carry `generated: true` and a bare literal body inherits it, so a filter on the
    # mark let `(if x, do: Server) |> then(& &1.new(x))` through (a review lane measured it,
    # and measured that the core's own four location-0 sites are already removed by the module
    # test). A second site in a transport is a second way to reach the core, however spelled.
    # Outside every static reading, stated: a module name built at runtime
    # (`Module.concat(["BeamMCP", "Server"]).new(x)`) leaves no site, no edge and no text hit;
    # the by-effect tests in transport/server_seam_test.exs are what hold that.
    sites =
      for {m, _loc, ctx} = site <- Boundary.atom_sites(BeamMCP.Server),
          m != BeamMCP.Server,
          do: {site, ctx}

    modules = sites |> Enum.map(fn {{m, _, _}, _} -> m end) |> Enum.sort()

    assert modules == Enum.uniq(modules),
           "BeamMCP.Server at more than one site in a module:\n  " <>
             Enum.map_join(sites, "\n  ", &inspect/1)

    # The transports are derived from the text: the files carrying the default line, in the
    # one spelling `@default` names (`opts`, the alias `Server`). A transport spelling it
    # otherwise is not in this set but its forms carry the atom, so the mismatch reads red,
    # never green; the fix is to spell the default as the two do, or to widen `@default` here.
    # Each of them is one of the modules above, and the modules above are exactly them.
    default_files = for {path, _, _} <- Boundary.hits(@default), uniq: true, do: path

    transports =
      for m <- Boundary.lib_modules(),
          source = to_string(m.module_info(:compile)[:source]),
          Path.relative_to(source, Boundary.root()) in default_files,
          do: m

    assert transports != [], "no transport carries the default `Server`"

    assert modules == Enum.sort(transports),
           "modules carrying BeamMCP.Server in their forms #{inspect(modules)} are not the transports #{inspect(Enum.sort(transports))}"
  end

  test "each transport names the default once and aliases the module once: the census is not reading an empty tree" do
    defaults = Boundary.hits(@default)
    default_files = for {path, _, _} <- defaults, do: path

    assert default_files == Enum.uniq(default_files),
           "the default `Server` more than once in a file:\n  " <> Boundary.format(defaults)

    assert length(default_files) >= 2,
           "fewer than two transports carry the default:\n  " <> Boundary.format(defaults)

    aliases = Boundary.hits(@alias)
    alias_files = for {path, _, _} <- aliases, do: path

    assert Enum.sort(alias_files) == Enum.sort(default_files),
           "the files aliasing BeamMCP.Server #{inspect(Enum.sort(alias_files))} are not the files carrying the default #{inspect(Enum.sort(default_files))}"
  end
end
