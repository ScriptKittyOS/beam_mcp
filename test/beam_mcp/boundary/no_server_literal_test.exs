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
  # would serve the default whatever the host passed. So, under lib/beam_mcp/transport/, the
  # only mentions of the module are the alias and the default value, read from the text, and
  # the compiled artefact carries no call edge from a transport module to `BeamMCP.Server`.
  use ExUnit.Case, async: true
  alias BeamMCP.Boundary

  @transports [BeamMCP.Transport.HTTP, BeamMCP.Transport.Stdio]
  @transport_dir "lib/beam_mcp/transport/"

  defp under_transport(hits),
    do: for({path, _, _} = hit <- hits, String.starts_with?(path, @transport_dir), do: hit)

  test "no line under lib/beam_mcp/transport/ calls BeamMCP.Server by name" do
    # A call is the module, a dot, a function name and an opening parenthesis; a doc line's
    # `BeamMCP.Server.new/1` is a reference, not a call, and `GenServer.stop(` has no word
    # boundary before `Server`.
    hits = under_transport(Boundary.hits(~r/\bServer\.\w+[!?]?\(/))

    assert hits == [],
           "BeamMCP.Server called by name under #{@transport_dir}:\n  " <> Boundary.format(hits)
  end

  test "from the artefact: no transport module calls a function of BeamMCP.Server" do
    {edges, _unresolved} = Boundary.xref()

    calls =
      for {{m, _, _} = from, {BeamMCP.Server, f, a}} <- edges, m in @transports, do: {from, f, a}

    assert calls == [],
           "edges from a transport to BeamMCP.Server:\n  " <>
             Enum.map_join(calls, "\n  ", &inspect/1)
  end

  test "each transport names the default once and aliases the module once: the census is not reading an empty tree" do
    defaults = under_transport(Boundary.hits(~r/Keyword\.(get|pop)\(opts, :server, Server\)/))

    assert Enum.sort(for {path, _, _} <- defaults, do: path) ==
             ["lib/beam_mcp/transport/http.ex", "lib/beam_mcp/transport/stdio.ex"],
           "the default `Server` under #{@transport_dir}:\n  " <> Boundary.format(defaults)

    aliases = under_transport(Boundary.hits(~r/^\s*alias BeamMCP\.Server$/))

    assert Enum.sort(for {path, _, _} <- aliases, do: path) ==
             ["lib/beam_mcp/transport/http.ex", "lib/beam_mcp/transport/stdio.ex"],
           "the alias under #{@transport_dir}:\n  " <> Boundary.format(aliases)
  end
end
