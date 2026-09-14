# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Connectome.Observed do
  @moduledoc """
  The observed connectome's collector: what the dispatch path emitted, as edges.

  A process the host adds to its own supervision tree -- the package starts nothing:

      children = [{BeamMCP.Connectome.Observed, name: MyApp.Observed}]

  Off unless started. While it runs it owns one ETS set and one `:telemetry` handler on
  `[:beam_mcp, :dispatch, :stop]` and `[:beam_mcp, :dispatch, :exception]`; every
  `tools/call` that reached the host's dispatch function becomes one row keyed by the canonical edge key -- the server node to the tool
  node, kind `:invoke`, provenance `:observed` -- with a call count and a latency summary.
  A repeated call is the same row with the count incremented; the table is bounded by the
  number of distinct edges, never by the number of calls.

  **Edge identity only.** No argument, result or header bytes enter the table: the handler
  reads the event's `server_name` and `tool` and its `duration`, and nothing else.

  **The table dies with this process.** It is created in `init/1` and is gone when the
  process is; a restart under the host's supervisor starts from no rows, so what a host
  loses on a crash is every observation since the last snapshot it kept. The declared
  connectome is unaffected -- it is built from the tree, not from what ran. A kill that
  skips `terminate/2` leaves the old handler attached until the restart replaces it; a
  call in that gap is answered normally, the stale handler fails against the missing table
  and telemetry detaches it, logging one failure per dispatching process that was in the
  gap (measured: sixteen concurrent callers, sixteen lines).

  **Writes happen in the caller's process**, not in this one. The table is `:public` with
  write concurrency, and the handler runs in whichever process dispatched the call; this
  process owns the table's lifetime and answers `snapshot/1`, and is never on the hot path.

  `snapshot/1` on a name that is not running is a named refusal, `{:error, :not_started}`,
  and not an empty graph: an empty observed connectome says "nothing ran", which is a
  different claim from "nothing was watching", and a diff that took the first for the
  second would report every declared edge as dead authority.
  """
  use GenServer

  alias BeamMCP.Connectome.{Edge, Graph, Node}

  # A call that returned and a call that raised are both an attempt, and the edge is the
  # attempt. `:exception` carries the host's raised exception in its metadata; the handler
  # never reads it.
  @events [[:beam_mcp, :dispatch, :stop], [:beam_mcp, :dispatch, :exception]]

  @typedoc """
  A row: the edge as identities -- `{from_identity, to_identity, kind}` -- the call count,
  and the latency sum and max in native time units. The canonical edge key and the nodes
  are derived from the identities at snapshot time, not on the hot path: deriving two id
  strings per call cost more than the write itself (measured, 013).
  """
  @type row ::
          {{Node.identity(), Node.identity(), Edge.kind()}, pos_integer(), non_neg_integer(),
           non_neg_integer()}

  @doc """
  Starts the collector. Options: `name:` (required; the registered name, also the table's).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, name, name: name)
  end

  @doc "A child spec whose id is the collector's name, so a host may run more than one."
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{id: Keyword.fetch!(opts, :name), start: {__MODULE__, :start_link, [opts]}}
  end

  @doc """
  The observed graph: one node per server and tool seen, one edge per row, weight the call
  count, every sign `:unknown`. `{:error, :not_started}` when no collector runs under `name`;
  `{:error, {:malformed_row, key}}` when a row in the public table is of a shape the
  builders would not write.
  """
  @spec snapshot(atom()) :: {:ok, Graph.t()} | {:error, :not_started | term()}
  def snapshot(name) do
    with {:ok, rows} <- fetch_rows(name),
         :ok <- well_formed(rows) do
      nodes =
        rows
        |> Enum.flat_map(fn {{from, to, _kind}, _count, _sum, _max} -> [from, to] end)
        |> Enum.uniq()
        |> Enum.map(&build_node/1)

      edges =
        for {{from, to, kind}, count, _sum, _max} <- rows do
          Edge.new!(
            from: Node.id(from),
            to: Node.id(to),
            kind: kind,
            provenance: :observed,
            weight: count
          )
        end

      Graph.new(nodes: nodes, edges: edges, schema_version: Graph.schema_version())
    end
  end

  @doc """
  The latency summary, per canonical edge key: the call count, the mean and the maximum in
  microseconds. A summary, never the samples. Not part of any hash.
  """
  @spec latency(atom()) ::
          %{Edge.key() => %{count: pos_integer(), mean_us: float(), max_us: float()}}
          | {:error, {:malformed_row, term()}}
  def latency(name) do
    with {:ok, rows} <- fetch_rows(name),
         :ok <- well_formed(rows) do
      Map.new(rows, fn {{from, to, kind}, count, sum, max} ->
        {{Node.id(from), Node.id(to), kind, :observed},
         %{
           count: count,
           mean_us: System.convert_time_unit(sum, :native, :nanosecond) / count / 1000,
           max_us: System.convert_time_unit(max, :native, :nanosecond) / 1000
         }}
      end)
    else
      {:error, :not_started} -> %{}
      {:error, _} = refusal -> refusal
    end
  end

  @doc "The rows as they are, for a reader that wants the table and not the graph."
  @spec rows(atom()) :: [row()]
  def rows(name) do
    case fetch_rows(name) do
      {:ok, rows} -> rows
      {:error, :not_started} -> []
    end
  end

  @doc "The number of rows: the number of distinct edges observed."
  @spec size(atom()) :: non_neg_integer()
  def size(name) do
    case :ets.whereis(name) do
      :undefined -> 0
      tid -> :ets.info(tid, :size)
    end
  end

  @impl true
  def init(name) do
    # Trap exits so a supervisor's shutdown reaches terminate/2 and the handler is detached
    # with the table. A kill skips terminate/2 and leaves the handler attached; a restart
    # must not trip over it, so the attach is made idempotent by detaching first. Found by
    # a lane that killed the collector under a real supervisor: the restarted init's attach
    # answered already_exists, the child crash-looped, and the host's supervisor went down.
    Process.flag(:trap_exit, true)

    ^name =
      :ets.new(name, [
        :set,
        :public,
        :named_table,
        {:write_concurrency, true},
        {:read_concurrency, true}
      ])

    _ = :telemetry.detach({__MODULE__, name})
    :ok = :telemetry.attach_many({__MODULE__, name}, @events, &__MODULE__.handle_event/4, name)
    {:ok, name}
  end

  @impl true
  def terminate(_reason, name) do
    :telemetry.detach({__MODULE__, name})
    :ok
  end

  @doc false
  # Runs in the dispatching process. Reads three things from the event and nothing else.
  def handle_event(_event, %{duration: duration}, %{server_name: server, tool: tool}, name) do
    observe(name, {:server, server}, {:tool, server, tool}, :invoke, duration)
  end

  @doc """
  Records one observation of the edge `from` → `to` of `kind` into the table under `name`,
  with a latency sample in native time units (0 when there is none). Identity only: the
  two node identities and a kind. This is what the telemetry handler and the tracer call;
  a host may call it too for an edge it observed by its own means.
  """
  @spec observe(atom(), Node.identity(), Node.identity(), Edge.kind(), non_neg_integer()) :: :ok
  def observe(name, from, to, kind, duration \\ 0) do
    key = {from, to, kind}
    duration = max(duration, 0)

    # Count and sum in one atomic step, inserting the row on first sight. The max is read
    # first and rewritten only when this sample is larger -- rare once the table is warm --
    # through an atomic compare-and-set, so two callers racing never lose the larger value.
    :ets.update_counter(name, key, [{2, 1}, {3, duration}], {key, 0, 0, 0})

    if :ets.lookup_element(name, key, 4) < duration do
      # `{:const, key}`: a key of nested tuples must be spelled as a constant in the body;
      # the `{key}` literal form was refused as not a match specification.
      :ets.select_replace(name, [
        {{key, :"$1", :"$2", :"$3"}, [{:<, :"$3", duration}],
         [{{{:const, key}, :"$1", :"$2", duration}}]}
      ])
    end

    :ok
  end

  defp fetch_rows(name) do
    case :ets.whereis(name) do
      :undefined -> {:error, :not_started}
      tid -> {:ok, :ets.tab2list(tid)}
    end
  end

  # The table is public, and observe/5 is a host's to call. A row of another shape -- an
  # identity the builder would not derive, a count below one -- is refused by its key,
  # never built into a graph and never raised with its bytes in a message.
  defp well_formed(rows) do
    Enum.find_value(rows, :ok, fn
      {{from, to, kind}, count, sum, max} = row
      when is_integer(count) and count >= 1 and is_integer(sum) and is_integer(max) ->
        if identity?(from) and identity?(to) and kind in [:invoke, :read, :message, :supervise],
          do: nil,
          else: {:error, {:malformed_row, elem(row, 0)}}

      row ->
        {:error, {:malformed_row, elem(row, 0)}}
    end)
  end

  defp identity?({:server, s}) when is_binary(s), do: true
  defp identity?({:tool, s, t}) when is_binary(s) and (is_atom(t) or is_binary(t)), do: true
  defp identity?({:process, s, p}) when is_binary(s) and is_atom(p), do: true
  defp identity?({:module, s, m}) when is_binary(s) and is_atom(m), do: true
  defp identity?(_), do: false

  # The node behind an identity, by the identity's own shape: the kind and level a builder
  # would give it. The four shapes the collector and the tracer write.
  defp build_node({:server, _} = identity),
    do: Node.new!(kind: :server, level: :server, identity: identity)

  defp build_node({:tool, _, _} = identity),
    do: Node.new!(kind: :tool, level: :server, identity: identity)

  defp build_node({:process, _, _} = identity),
    do: Node.new!(kind: :process, level: :server, identity: identity)

  defp build_node({:module, _, m} = identity) when is_atom(m),
    do: Node.new!(kind: :module, level: :module, identity: identity)
end
