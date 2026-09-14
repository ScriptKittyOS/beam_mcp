# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Fixture.Livebook do
  @moduledoc false
  # The four exports the Livebook under livebooks/ reads, built by the package from the
  # declared fixture and one run of the collector, so a test can hold the tracked files to
  # what the package produces today. The running server's catalog carries one tool the
  # declared catalog does not (`probe`): the drift the diff exists to find. No sign is set on
  # either side, so the export shows three of the four classes; `changed_sign` needs a
  # consumer to have supplied a sign on both sides, which nothing here does.
  alias BeamMCP.Connectome.{Canonical, Declared, Diff, Graph, Observed}
  alias BeamMCP.Fixture.Declared, as: Fx
  alias BeamMCP.Server

  @server "fx"
  @modules [Fx.Alpha, Fx.Beta, Fx.Gamma, Fx.MacroOnly, Fx.Dyn, Fx.Catalog]
  @window %{"started_at" => "2026-09-14T00:00:00Z", "ended_at" => "2026-09-14T01:00:00Z"}

  defmodule RunningCatalog do
    @moduledoc false
    @behaviour BeamMCP.Catalog

    @impl true
    def capabilities do
      %{
        tools: [
          %BeamMCP.ToolSpec{
            name: :echo,
            command_class: :observe,
            mode: :read_only,
            description: "Echo."
          },
          %BeamMCP.ToolSpec{
            name: :write,
            command_class: :mutate,
            mode: :proposal,
            description: "Write."
          },
          %BeamMCP.ToolSpec{
            name: :probe,
            command_class: :observe,
            mode: :read_only,
            description: "Running, never declared."
          }
        ],
        resources: [],
        prompts: []
      }
    end
  end

  @doc "File name => bytes, for every export the notebook reads."
  def exports do
    {:ok, %Declared.Result{graph: declared}} =
      Declared.build(
        server: @server,
        catalog: Fx.Catalog,
        modules: @modules,
        tool_modules: %{echo: Fx.Alpha}
      )

    observed = observe()
    {:ok, diff} = Diff.run(declared, observed, window: @window)

    %{
      "fx.declared.json" => Canonical.to_json!(declared),
      "fx.observed.json" => Canonical.to_json!(observed),
      "fx.observed.sidecar.json" => Canonical.sidecar!(observed),
      "fx.diff.json" => Diff.encode!(diff)
    }
  end

  # Three calls to echo, one to write, one to the undeclared probe, through the one dispatch
  # site the span is on; the collector's table is the observed graph.
  defp observe do
    name = Module.concat(__MODULE__, :"c#{System.unique_integer([:positive])}")
    {:ok, pid} = Observed.start_link(name: name)

    state =
      Server.new(
        dispatch: fn _name, _args, _opts -> {:ok, %{}} end,
        catalog: RunningCatalog,
        server_name: @server
      )

    for tool <- [:echo, :echo, :echo, :write, :probe] do
      {_state, %{"result" => _}} =
        Server.handle_message(state, %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "tools/call",
          "params" => %{"name" => Atom.to_string(tool), "arguments" => %{}}
        })
    end

    {:ok, graph} = Observed.snapshot(name)
    :ok = GenServer.stop(pid)
    only_fx(graph)
  end

  # The collector is node-wide: every dispatch on the node lands in its table, whatever the
  # server, and the test suite runs other servers beside this one. The export is the
  # collector's graph restricted to `fx` -- the ids carry the server, so the restriction is
  # by id and not by guess.
  defp only_fx(%Graph{} = graph) do
    fx? = &String.starts_with?(&1, @server <> "/")

    Graph.new!(
      nodes: Enum.filter(graph.nodes, &fx?.(&1.id)),
      edges: Enum.filter(graph.edges, &(fx?.(&1.from) and fx?.(&1.to))),
      schema_version: graph.schema_version
    )
  end
end
