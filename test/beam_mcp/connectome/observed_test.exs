# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Connectome.ObservedTest do
  @moduledoc """
  The observed collector: telemetry from the dispatch path into a bounded ETS set, keyed by
  the canonical edge key, and out again as a Graph whose provenance is `:observed` and whose
  every sign is `:unknown`.

  Edge identity only. The marker tests are the ones that matter: a string a host put in an
  argument, a resource URI, an error or an exception must be absent from every row, from the
  snapshot's canonical bytes, from the sidecar and from the latency summary.
  """
  use ExUnit.Case, async: false
  use ExUnitProperties

  alias BeamMCP.Connectome.{Canonical, Edge, Graph, Node, Observed}
  alias BeamMCP.Fixture.ObservedCatalog, as: Catalog
  alias BeamMCP.Server
  alias BeamMCP.Transport.HTTP

  @marker "PAYLOAD-MARKER-7f3a9c"
  @server_name "srv"

  # A collector whose every start after the first waits, so a supervisor's restart gap can
  # be held open long enough to call into it.
  defmodule SlowRestart do
    def child_spec(opts) do
      %{id: __MODULE__, start: {__MODULE__, :start_link, [opts]}}
    end

    def start_link(opts) do
      {flag, opts} = Keyword.pop!(opts, :flag)
      if :persistent_term.get(flag, false), do: Process.sleep(300)
      :persistent_term.put(flag, true)
      Observed.start_link(opts)
    end
  end

  # A collector under a fresh name per test; the process is linked to the test and its
  # table dies with it.
  defp start_collector(opts \\ []) do
    name = Module.concat(__MODULE__, :"c#{System.unique_integer([:positive])}")
    pid = start_supervised!({Observed, Keyword.merge([name: name], opts)})
    {name, pid}
  end

  defp server(dispatch) do
    Server.new(dispatch: dispatch, catalog: Catalog, server_name: @server_name)
  end

  defp call(state, tool, arguments \\ %{}) do
    Server.handle_message(state, %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "tools/call",
      "params" => %{"name" => Atom.to_string(tool), "arguments" => arguments}
    })
  end

  defp ok_dispatch, do: fn _name, _args, _opts -> {:ok, %{"done" => true}} end

  # A dispatch that hands its arguments back to the test, so a marker test can first prove
  # the marker reached the dispatch function -- a schema-less tool drops undeclared keys
  # before dispatch, and the first marker tests were vacuous for exactly that reason.
  defp reporting_dispatch(test, reply) do
    fn _name, args, _opts ->
      send(test, {:dispatched, args})
      reply.()
    end
  end

  # A function with one clause that no dispatch argument matches: the BEAM's
  # function_clause error puts the arguments in the stacktrace's top frame.
  def no_clause_for(:never), do: :ok

  defp flush do
    receive do
      _ -> flush()
    after
      0 -> :ok
    end
  end

  defp assert_dispatch_saw_marker do
    assert_receive {:dispatched, args}
    assert inspect(args, limit: :infinity, printable_limit: :infinity) =~ @marker
  end

  # A handler as a named function: telemetry warns about a local function (it is slower to
  # call), and a host attaching in anger would not use one either.
  def forward(event, measurements, metadata, test),
    do: send(test, {event, measurements, metadata})

  describe "snapshot/1 when nothing is watching" do
    test "a collector that was never started is a named refusal, not an empty graph" do
      # An empty observed connectome says "nothing ran"; a collector that is not running says
      # "nothing was watching". A diff that took the first for the second would report every
      # declared edge as dead authority.
      assert Observed.snapshot(:"#{__MODULE__}.never_started") == {:error, :not_started}
    end

    test "the readers answer the not-started case each in their own type: no rows, no latency, size zero" do
      never = :"#{__MODULE__}.never_started_either"
      assert Observed.rows(never) == []
      assert Observed.latency(never) == %{}
      assert Observed.size(never) == 0
    end

    test "a started collector that has seen no calls is an empty graph, distinct from the refusal" do
      {name, _pid} = start_collector()
      assert {:ok, %Graph{nodes: [], edges: []}} = Observed.snapshot(name)
    end

    test "the table dies with its owner: after the collector stops, snapshot/1 refuses by name again" do
      {name, pid} = start_collector()
      state = server(ok_dispatch())
      call(state, :echo)
      assert {:ok, %Graph{edges: [_]}} = Observed.snapshot(name)

      :ok = stop_supervised!(name)
      refute Process.alive?(pid)
      assert Observed.snapshot(name) == {:error, :not_started}

      # And its handler went with it: a handler left behind would fail against the missing
      # table on the next call and be detached by telemetry with an error logged -- found
      # when a test's collectors outlived their tests.
      ids = Enum.map(:telemetry.list_handlers([:beam_mcp, :dispatch, :stop]), & &1.id)
      refute {Observed, name} in ids
    end
  end

  describe "under a real supervisor" do
    test "a kill is survived: the supervisor lives, the collector restarts from no rows, one handler, not two" do
      # Found by a lane running the collector as a host would: a :kill skips terminate/2,
      # the handler stayed attached, the restarted init's attach got already_exists, the
      # child crash-looped and the HOST'S supervisor exited. The doc had promised a restart
      # from no rows; nothing had tested a restart.
      name = :"#{__MODULE__}.killed"
      {:ok, sup} = Supervisor.start_link([{Observed, name: name}], strategy: :one_for_one)
      Process.unlink(sup)
      on_exit(fn -> if Process.alive?(sup), do: Supervisor.stop(sup) end)

      call(server(ok_dispatch()), :echo)
      assert {:ok, %Graph{edges: [_]}} = Observed.snapshot(name)

      pid = Process.whereis(name)
      ref = Process.monitor(pid)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}

      # The supervisor restarts it; wait for the new registration.
      new =
        Enum.find_value(1..50, fn _ ->
          Process.sleep(10)

          case Process.whereis(name) do
            nil -> nil
            p when p != pid -> p
          end
        end)

      assert Process.alive?(sup)
      assert is_pid(new)
      assert {:ok, %Graph{nodes: [], edges: []}} = Observed.snapshot(name)

      ids = Enum.map(:telemetry.list_handlers([:beam_mcp, :dispatch, :stop]), & &1.id)
      assert Enum.count(ids, &(&1 == {Observed, name})) == 1

      call(server(ok_dispatch()), :echo)
      assert {:ok, %Graph{edges: [%Edge{weight: 1}]}} = Observed.snapshot(name)
    end

    test "a call during the restart gap is answered, the stale handler is detached once, and the restarted collector counts from no rows" do
      # A consumer lane ran this as a script for four rounds; it is a page claim a host relies
      # on, so it is a test. The child's second start is slowed to hold the gap open.
      name = :"#{__MODULE__}.gap_#{System.unique_integer([:positive])}"
      slow = {SlowRestart, :started, name}
      on_exit(fn -> :persistent_term.erase(slow) end)

      {:ok, sup} =
        Supervisor.start_link([{SlowRestart, name: name, flag: slow}], strategy: :one_for_one)

      Process.unlink(sup)
      on_exit(fn -> if Process.alive?(sup), do: Supervisor.stop(sup) end)

      state = server(ok_dispatch())
      call(state, :echo)
      assert Observed.size(name) == 1

      pid = Process.whereis(name)
      ref = Process.monitor(pid)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}

      # The gap: no collector, the dead one's handler still attached. The call is answered,
      # not crashed; telemetry detaches the stale handler with one log line, so the next
      # call in the gap is silent.
      assert Observed.snapshot(name) == {:error, :not_started}
      assert {_, %{"result" => %{"isError" => false}}} = call(state, :echo)
      ids = Enum.map(:telemetry.list_handlers([:beam_mcp, :dispatch, :stop]), & &1.id)
      refute {Observed, name} in ids
      assert {_, %{"result" => %{"isError" => false}}} = call(state, :echo)

      # The restart lands; the new collector counts from no rows, with one handler.
      new =
        Enum.find_value(1..100, fn _ ->
          Process.sleep(10)
          if (p = Process.whereis(name)) && p != pid, do: p
        end)

      assert is_pid(new)
      assert {:ok, %Graph{edges: []}} = Observed.snapshot(name)
      call(state, :echo)
      assert {:ok, %Graph{edges: [%Edge{weight: 1}]}} = Observed.snapshot(name)
      ids = Enum.map(:telemetry.list_handlers([:beam_mcp, :dispatch, :stop]), & &1.id)
      assert Enum.count(ids, &(&1 == {Observed, name})) == 1
    end

    test "a hot reload of the collector's module keeps the process, its handler and its rows, idle and under load" do
      # The handler is an external fun, not a closure over a code version, so a purge does
      # not detach it; the table lives in the process, not the module.
      {name, pid} = start_collector()
      state = server(ok_dispatch())
      call(state, :echo)

      reload = fn ->
        :code.purge(Observed)
        {:module, Observed} = :code.load_file(Observed)
        :code.purge(Observed)
      end

      reload.()
      assert Process.whereis(name) == pid and Process.alive?(pid)
      assert {_, %{"result" => %{"isError" => false}}} = call(state, :echo)
      assert {:ok, %Graph{edges: [%Edge{weight: 2}]}} = Observed.snapshot(name)

      task = Task.async(fn -> for _ <- 1..500, do: call(state, :echo) end)
      reload.()
      Task.await(task, 30_000)
      assert Process.alive?(pid)
      assert {:ok, %Graph{edges: [%Edge{weight: 502}]}} = Observed.snapshot(name)
      ids = Enum.map(:telemetry.list_handlers([:beam_mcp, :dispatch, :stop]), & &1.id)
      assert Enum.count(ids, &(&1 == {Observed, name})) == 1
    end

    test "the handler runs in the dispatching process, never in the owner" do
      {name, owner} = start_collector()
      test = self()

      state =
        server(fn _, _, _ ->
          send(test, {:dispatching_in, self()})
          {:ok, %{}}
        end)

      call(state, :echo)
      assert_receive {:dispatching_in, dispatcher}
      assert dispatcher == self()
      assert owner != dispatcher
      # The row is there without the owner having been asked anything: its mailbox is empty
      # and it answered nothing, because the write went straight to the table.
      assert {:message_queue_len, 0} = Process.info(owner, :message_queue_len)
      assert Observed.size(name) == 1
    end
  end

  describe "a foreign row" do
    # The table is public and observe/5 is a host's to call; a row of another shape is
    # refused by name, never built into a graph and never raised with its bytes.
    test "a malformed row written by a third party is refused by name by snapshot/1 and latency/1" do
      {name, _} = start_collector()
      call(server(ok_dispatch()), :echo)
      bad = {{:tool, "s", {:payload, @marker}}, {:server, "s"}, :invoke}
      true = :ets.insert(name, {bad, 1, 0, 0})
      assert {:error, {:malformed_row, ^bad}} = Observed.snapshot(name)
      assert {:error, {:malformed_row, ^bad}} = Observed.latency(name)

      true = :ets.delete(name, bad)
      zero = {{:server, "s"}, {:tool, "s", :echo}, :invoke}
      true = :ets.insert(name, {zero, 0, 0, 0})
      assert {:error, {:malformed_row, ^zero}} = Observed.snapshot(name)
      assert {:error, {:malformed_row, ^zero}} = Observed.latency(name)
    end
  end

  describe "one call, one edge" do
    test "exercising one fixture tool call produces exactly one observed edge with weight >= 1" do
      {name, _} = start_collector()
      state = server(ok_dispatch())
      {_state, %{"result" => _}} = call(state, :echo)

      assert {:ok, %Graph{} = g} = Observed.snapshot(name)
      assert [%Edge{} = e] = g.edges
      assert e.weight >= 1
      assert e.kind == :invoke
      assert e.provenance == :observed
      assert e.sign == :unknown
      # The ids are the ones the declared builder would derive for the same server and tool,
      # so the two graphs join.
      assert e.from == Node.id({:server, @server_name})
      assert e.to == Node.id({:tool, @server_name, :echo})
      assert Enum.map(g.nodes, & &1.id) |> Enum.sort() == Enum.sort([e.from, e.to])
      # Observed nodes carry no labels: the collector saw a call, not a catalog entry.
      assert Enum.all?(g.nodes, &(&1.labels == %{}))
    end

    test "a declared but uninvoked tool produces no observed edge" do
      {name, _} = start_collector()
      state = server(ok_dispatch())
      call(state, :echo)

      {:ok, g} = Observed.snapshot(name)
      write = Node.id({:tool, @server_name, :write})
      refute Enum.any?(g.edges, &(&1.to == write))
      refute Enum.any?(g.nodes, &(&1.id == write))
    end

    test "a failed call is still one edge: the edge is the attempt, not the outcome" do
      {name, _} = start_collector()
      state = server(fn _, _, _ -> {:error, "nope"} end)
      {_state, %{"result" => %{"isError" => true}}} = call(state, :echo)
      assert {:ok, %Graph{edges: [%Edge{weight: 1}]}} = Observed.snapshot(name)
    end
  end

  property "N repeated calls are one row with weight N, and the table is bounded by distinct edges, not by N" do
    check all(n <- integer(1..40), max_runs: 20) do
      {name, _} = start_collector()
      state = server(ok_dispatch())
      for _ <- 1..n, do: call(state, :echo)

      assert {:ok, %Graph{edges: [%Edge{weight: ^n}]}} = Observed.snapshot(name)
      assert Observed.size(name) == 1
      :ok = stop_supervised!(name)
    end
  end

  describe "edge identity only: the marker never enters" do
    # The marker travels every way a host could send it: nested inside an argument map, as a
    # resource URI argument, in the error a dispatch returns, in the exception a dispatch
    # raises. It must be absent from the rows, the canonical bytes, the sidecar and the
    # latency summary.
    test "a marker in a nested argument map and in a uri argument is absent from rows, bytes, sidecar and latency" do
      {name, _} = start_collector()
      state = server(reporting_dispatch(self(), fn -> {:ok, %{"done" => true}} end))

      call(state, :echo, %{
        "note" => %{"deep" => %{"deeper" => @marker}},
        "uri" => "r://#{@marker}/x"
      })

      assert_dispatch_saw_marker()
      assert_marker_absent(name)
    end

    test "a marker in the error a dispatch returns is absent" do
      {name, _} = start_collector()
      state = server(reporting_dispatch(self(), fn -> {:error, "failed: #{@marker}"} end))
      call(state, :echo, %{"k" => @marker})
      assert_dispatch_saw_marker()
      assert_marker_absent(name)
    end

    test "a marker in an exception a dispatch raises is absent, and the edge was still recorded" do
      {name, _} = start_collector()
      state = server(reporting_dispatch(self(), fn -> raise "exploded: #{@marker}" end))

      assert_raise RuntimeError, ~r/exploded/, fn -> call(state, :echo, %{"k" => @marker}) end

      assert_dispatch_saw_marker()
      assert_marker_absent(name)
      assert {:ok, %Graph{edges: [%Edge{weight: 1}]}} = Observed.snapshot(name)
    end

    test "the :stop event itself carries no argument, result or header bytes" do
      {name, _} = start_collector()
      id = {__MODULE__, :probe, System.unique_integer()}
      :ok = :telemetry.attach(id, [:beam_mcp, :dispatch, :stop], &__MODULE__.forward/4, self())

      on_exit(fn -> :telemetry.detach(id) end)
      state = server(reporting_dispatch(self(), fn -> {:ok, %{"echo" => @marker}} end))
      call(state, :echo, %{"k" => @marker})
      assert_dispatch_saw_marker()

      assert_receive {[:beam_mcp, :dispatch, :stop], measurements, metadata}
      refute inspect(measurements) =~ @marker
      refute inspect(metadata) =~ @marker
      assert metadata.server_name == @server_name
      assert metadata.tool == :echo
      assert metadata.outcome == :ok
      assert is_integer(measurements.duration)
      _ = name
    end

    defp assert_marker_absent(name) do
      rows = Observed.rows(name)
      assert rows != []
      refute inspect(rows, limit: :infinity, printable_limit: :infinity) =~ @marker

      {:ok, g} = Observed.snapshot(name)
      refute Canonical.encode!(g) =~ @marker
      refute Canonical.sidecar!(g) =~ @marker

      refute inspect(Observed.latency(name), limit: :infinity, printable_limit: :infinity) =~
               @marker
    end
  end

  describe "the events, as a contract" do
    test "start and stop are emitted around every tools/call with the documented names and shapes" do
      id = {__MODULE__, :contract, System.unique_integer()}

      :ok =
        :telemetry.attach_many(
          id,
          [[:beam_mcp, :dispatch, :start], [:beam_mcp, :dispatch, :stop]],
          &__MODULE__.forward/4,
          self()
        )

      on_exit(fn -> :telemetry.detach(id) end)
      call(server(ok_dispatch()), :echo)

      assert_receive {[:beam_mcp, :dispatch, :start], %{system_time: _, monotonic_time: _},
                      start_meta}

      assert_receive {[:beam_mcp, :dispatch, :stop], %{duration: _, monotonic_time: _}, stop_meta}
      assert %{server_name: @server_name, tool: :echo, telemetry_span_context: ctx} = start_meta

      assert %{server_name: @server_name, tool: :echo, outcome: :ok, telemetry_span_context: ^ctx} =
               stop_meta

      assert map_size(start_meta) == 3 and map_size(stop_meta) == 4

      call(server(fn _, _, _ -> {:error, "no"} end), :echo)
      assert_receive {[:beam_mcp, :dispatch, :stop], _, %{outcome: :error}}

      # A call the schema refuses, and a call to no tool, are not dispatches: nothing emits.
      # (The error call above left its :start in the mailbox; flush first.)
      flush()
      {_, %{"result" => %{"isError" => true}}} = call(server(ok_dispatch()), :echo, %{"k" => 1})
      {_, %{"error" => _}} = call(server(ok_dispatch()), :no_such_tool)
      refute_receive {[:beam_mcp, :dispatch, _], _, _}, 100
    end

    test "exception is span/3's own shape: the host's raised reason travels in it, and the collector still counts the attempt" do
      id = {__MODULE__, :exception, System.unique_integer()}

      :ok =
        :telemetry.attach(id, [:beam_mcp, :dispatch, :exception], &__MODULE__.forward/4, self())

      on_exit(fn -> :telemetry.detach(id) end)
      {name, _} = start_collector()

      assert_raise RuntimeError, fn ->
        call(server(fn _, _, _ -> raise "host's own: #{@marker}" end), :echo)
      end

      assert_receive {[:beam_mcp, :dispatch, :exception], %{duration: _, monotonic_time: _}, meta}

      assert %{
               server_name: @server_name,
               tool: :echo,
               kind: :error,
               reason: %RuntimeError{},
               stacktrace: _,
               telemetry_span_context: ctx
             } = meta

      assert is_reference(ctx) and map_size(meta) == 6
      refute Map.has_key?(meta, :outcome)
      # The document says so: the reason is the host's, and travels as span/3 defines.
      assert Exception.message(meta.reason) =~ @marker
      assert_marker_absent(name)
    end

    test "a throw and an exit from the dispatch are exceptions of their kind, with marker-free frames; a crafted error_info is dropped from the frames" do
      id = {__MODULE__, :kinds, System.unique_integer()}

      :ok =
        :telemetry.attach(id, [:beam_mcp, :dispatch, :exception], &__MODULE__.forward/4, self())

      on_exit(fn -> :telemetry.detach(id) end)
      {name, _} = start_collector()

      for {kind, dispatch} <- [
            {:throw, fn _, args, _ -> throw({:payload, args}) end},
            {:exit, fn _, args, _ -> exit({:payload, args}) end},
            # A host can put a term in a frame's location keywords through error_info; the
            # frames keep file and line and drop the rest.
            {:error,
             fn _, args, _ -> :erlang.error(:crafted, [args], error_info: %{cause: args}) end}
          ] do
        catch_of = fn -> call(server(dispatch), :echo, %{"k" => @marker}) end

        case kind do
          :throw -> catch_throw(catch_of.())
          :exit -> catch_exit(catch_of.())
          :error -> assert_raise ErlangError, catch_of
        end

        assert_receive {[:beam_mcp, :dispatch, :exception], _, %{kind: ^kind, stacktrace: frames}}
        refute inspect(frames, limit: :infinity, printable_limit: :infinity) =~ @marker
      end

      assert_marker_absent(name)
    end

    test "a host-built stacktrace cannot break the catch clause: odd frames are made plain, the event still fires, and the host's own error and stacktrace are re-raised untouched" do
      # A lane raised through `:erlang.raise/3` with frames no compiler writes: a location
      # that is not a keyword list, an improper argument list, a file and a line of the wrong
      # type. The rewrite raised inside the catch clause -- `:start` with no `:exception`,
      # no row, and the host's error replaced by ours. (A location that is not a list at
      # all never arrives: `:erlang.raise/3` answers `:badarg` for it instead of raising.)
      id = {__MODULE__, :built, System.unique_integer()}

      :ok =
        :telemetry.attach_many(
          id,
          [[:beam_mcp, :dispatch, :stop], [:beam_mcp, :dispatch, :exception]],
          &__MODULE__.forward/4,
          self()
        )

      on_exit(fn -> :telemetry.detach(id) end)
      {name, _} = start_collector()

      # The arity position too: a lane put the arguments there, as a map, a tuple, a
      # binary and an atom, and each travelled verbatim. A frame whose arity is neither
      # a list nor an integer is no frame the BEAM writes, and is dropped.
      built = fn args ->
        [
          {Enum, :x, 1, [args]},
          {Enum, :y, [args | args], []},
          {Enum, :z, 2, [file: @marker, line: @marker]},
          {Enum, :w, 0, [file: ~c"a.ex", line: 7, error_info: %{cause: args}]},
          {Enum, :u, 1, [file: [args], line: 1.5]},
          {Enum, :t, args, []},
          {Enum, :s, {args, @marker}, []},
          {Enum, :r, @marker, []},
          {Enum, :q, :"#{@marker}", []}
        ]
      end

      dispatch = fn _, args, _ -> :erlang.raise(:error, {:crafted, args}, built.(args)) end

      {reason, raised} =
        try do
          call(server(dispatch), :echo, %{"k" => @marker})
        catch
          :error, reason -> {reason, __STACKTRACE__}
        end

      assert {:crafted, %{k: @marker} = args} = reason
      assert raised == built.(args)

      assert_receive {[:beam_mcp, :dispatch, :exception], _,
                      %{kind: :error, reason: ^reason, stacktrace: frames}}

      assert frames == [
               {Enum, :x, 1, []},
               {Enum, :y, 1, []},
               {Enum, :z, 2, []},
               {Enum, :w, 0, [file: ~c"a.ex", line: 7]},
               {Enum, :u, 1, []}
             ]

      refute inspect(frames, limit: :infinity, printable_limit: :infinity) =~ @marker
      refute_received {[:beam_mcp, :dispatch, :stop], _, _}
      assert {:ok, %Graph{edges: [%Edge{weight: 1}]}} = Observed.snapshot(name)
      assert_marker_absent(name)
    end

    test "dispatch_opts never enter: a secret handed to every dispatch is in no row, byte or summary" do
      test = self()

      dispatch = fn _, _args, opts ->
        send(test, {:opts, opts})
        {:ok, %{}}
      end

      {name, _} = start_collector()

      state =
        Server.new(
          dispatch: dispatch,
          catalog: Catalog,
          server_name: @server_name,
          dispatch_opts: [secret: @marker]
        )

      assert {_, %{"result" => _}} = call(state, :echo, %{"k" => "plain"})
      assert_receive {:opts, [secret: @marker]}
      assert_marker_absent(name)
    end

    test "the :exception stacktrace carries arities, never arguments: a function_clause or a BIF error would have put the call's arguments in its top frame" do
      # An adversarial read found the BEAM's own stacktrace carrying the argument list for
      # a function_clause and for a BIF badarg -- three of four common failure shapes --
      # while the page said no argument bytes are in any event.
      id = {__MODULE__, :frames, System.unique_integer()}

      :ok =
        :telemetry.attach(id, [:beam_mcp, :dispatch, :exception], &__MODULE__.forward/4, self())

      on_exit(fn -> :telemetry.detach(id) end)
      {name, _} = start_collector()

      for dispatch <- [
            fn _, args, _ -> :erlang.binary_to_atom(args, :utf8) end,
            fn _, args, _ -> Map.fetch!(args, :missing) end,
            fn _, args, _ -> __MODULE__.no_clause_for(args) end
          ] do
        state =
          server(reporting_dispatch(self(), fn -> :unused end) |> then(fn _ -> dispatch end))

        try do
          call(state, :echo, %{"k" => @marker})
        rescue
          _ -> :raised
        end

        assert_receive {[:beam_mcp, :dispatch, :exception], _, %{stacktrace: frames}}
        refute inspect(frames, limit: :infinity, printable_limit: :infinity) =~ @marker

        for frame <- frames do
          assert {_m, _f, arity, _loc} = frame
          assert is_integer(arity)
        end
      end

      assert_marker_absent(name)
    end
  end

  describe "through the HTTP transport" do
    import Plug.Test
    import Plug.Conn

    test "request headers carrying the marker reach neither the events nor the rows" do
      id = {__MODULE__, :http, System.unique_integer()}

      :ok =
        :telemetry.attach_many(
          id,
          [[:beam_mcp, :dispatch, :start], [:beam_mcp, :dispatch, :stop]],
          &__MODULE__.forward/4,
          self()
        )

      on_exit(fn -> :telemetry.detach(id) end)
      {name, _} = start_collector()

      opts =
        HTTP.init(
          catalog: Catalog,
          dispatch: fn _, a, _ -> {:ok, a} end,
          authorize: fn _ -> :ok end,
          allowed_origins: :any,
          server_name: @server_name
        )

      body = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{"name" => "echo", "arguments" => %{"k" => "v"}}
      }

      conn =
        :post
        |> conn("/mcp", Jason.encode!(body))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("mcp-protocol-version", "2026-07-28")
        |> put_req_header("mcp-method", "tools/call")
        |> put_req_header("mcp-name", "echo")
        |> put_req_header("authorization", "Bearer #{@marker}")
        |> put_req_header("x-secret", @marker)
        |> put_req_header("user-agent", @marker)
        |> HTTP.call(opts)

      assert conn.status == 200
      assert_receive {[:beam_mcp, :dispatch, :start], _, start_meta}
      assert_receive {[:beam_mcp, :dispatch, :stop], _, stop_meta}
      refute inspect(start_meta) =~ @marker
      refute inspect(stop_meta) =~ @marker
      assert_marker_absent(name)
    end
  end

  describe "latency/1" do
    test "a summary per edge: count, mean and max in microseconds, never a raw sample list" do
      {name, _} = start_collector()
      state = server(ok_dispatch())
      for _ <- 1..3, do: call(state, :echo)

      key =
        {Node.id({:server, @server_name}), Node.id({:tool, @server_name, :echo}), :invoke,
         :observed}

      assert %{^key => %{count: 3, mean_us: mean, max_us: max}} = Observed.latency(name)
      # Both in microseconds as floats from the native samples, so the mean of the samples
      # is never above the largest of them by a rounding.
      assert is_float(mean) and is_float(max) and max >= 0 and mean <= max
    end
  end
end
