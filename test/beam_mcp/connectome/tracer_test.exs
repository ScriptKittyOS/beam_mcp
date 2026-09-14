# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Connectome.TracerTest do
  @moduledoc """
  The guarded tracer: opt-in, off by default, one at a time, stops itself at its limits,
  leaves nothing behind, and writes identity only -- a module-to-module `:invoke` from a
  traced call, a name-to-name `:message` from a traced send -- into the collector's table.
  """
  use ExUnit.Case, async: false

  alias BeamMCP.Connectome.{Edge, Graph, Node, Observed, Tracer}
  alias BeamMCP.Fixture.Declared.{Alpha, Beta, Dyn}

  @marker "PAYLOAD-MARKER-1b2c3d"
  @server "srv"

  setup do
    name = Module.concat(__MODULE__, :"c#{System.unique_integer([:positive])}")
    start_supervised!({Observed, name: name})
    on_exit(fn -> Tracer.stop() end)
    {:ok, collector: name}
  end

  defp start(collector, opts) do
    Tracer.start(Keyword.merge([collector: collector, server: @server], opts))
  end

  describe "off by default, and guarded" do
    test "nothing is traced until a host starts the tracer: no flags on any process, no pattern on any module",
         %{
           collector: _
         } do
      refute Tracer.running?()
      {:flags, flags} = :erlang.trace_info(self(), :flags)
      assert flags == []
      assert {:traced, false} = :erlang.trace_info({Alpha, :run, 1}, :traced)
    end

    test "a second tracer is refused while one runs; one at a time", %{collector: c} do
      assert {:ok, _pid} = start(c, modules: [Alpha])
      assert {:error, :already_running} = start(c, modules: [Alpha])
      assert :ok = Tracer.stop()
      refute Tracer.running?()
    end

    test "it refuses to start without a running collector to write to" do
      assert {:error, :collector_not_started} =
               Tracer.start(
                 collector: :"#{__MODULE__}.nowhere",
                 server: @server,
                 modules: [Alpha]
               )

      refute Tracer.running?()
    end

    test "a limit is required to be positive and finite; there is no unbounded mode", %{
      collector: c
    } do
      assert {:error, {:invalid, :max_messages, 0}} = start(c, modules: [Alpha], max_messages: 0)

      assert {:error, {:invalid, :max_duration_ms, :infinity}} =
               start(c, modules: [Alpha], max_duration_ms: :infinity)
    end
  end

  describe "stops itself" do
    test "at max_messages: the count is reached, tracing is off, every pattern is cleared, nothing left behind",
         %{
           collector: c
         } do
      {:ok, pid} = start(c, modules: [Alpha, Beta], max_messages: 5, max_duration_ms: 60_000)
      ref = Process.monitor(pid)
      for _ <- 1..50, do: Alpha.run(1)
      assert_receive {:DOWN, ^ref, :process, ^pid, {:shutdown, {:limit, :max_messages, 5}}}, 2_000

      refute Tracer.running?()
      assert {:traced, false} = :erlang.trace_info({Alpha, :run, 1}, :traced)
      assert {:traced, false} = :erlang.trace_info({Beta, :run, 1}, :traced)
      {:flags, flags} = :erlang.trace_info(self(), :flags)
      assert flags == []
    end

    test "at max_duration_ms: the clock runs out, tracing is off, patterns cleared", %{
      collector: c
    } do
      {:ok, pid} = start(c, modules: [Alpha], max_messages: 1_000_000, max_duration_ms: 50)
      ref = Process.monitor(pid)

      assert_receive {:DOWN, ^ref, :process, ^pid, {:shutdown, {:limit, :max_duration_ms, 50}}},
                     2_000

      assert {:traced, false} = :erlang.trace_info({Alpha, :run, 1}, :traced)
    end

    test "stop/0 is the third way out, and clears the same way", %{collector: c} do
      {:ok, _} = start(c, modules: [Alpha])
      assert {:traced, true} = :erlang.trace_info({Alpha, :run, 1}, :traced)
      :ok = Tracer.stop()
      assert {:traced, false} = :erlang.trace_info({Alpha, :run, 1}, :traced)
      assert :ok = Tracer.stop()
    end
  end

  describe "what it writes" do
    test "a traced call is a module-level :invoke edge from the caller's module to the callee's, and nothing of the arguments",
         %{
           collector: c
         } do
      {:ok, _} = start(c, modules: [Beta])
      Alpha.run(@marker)
      :ok = Tracer.stop()

      {:ok, %Graph{} = g} = Observed.snapshot(c)
      from = Node.id({:module, @server, Alpha})
      to = Node.id({:module, @server, Beta})

      assert [%Edge{from: ^from, to: ^to, kind: :invoke, provenance: :observed, sign: :unknown}] =
               g.edges

      assert Enum.all?(g.nodes, &(&1.kind == :module and &1.level == :module))
      refute inspect(Observed.rows(c), limit: :infinity) =~ @marker
    end

    test "a dynamic call through apply/3 is the same edge as a static one", %{collector: c} do
      {:ok, _} = start(c, modules: [Beta])
      Dyn.apply_to(Beta, [@marker])
      :ok = Tracer.stop()

      {:ok, g} = Observed.snapshot(c)
      from = Node.id({:module, @server, Dyn})
      to = Node.id({:module, @server, Beta})
      assert [%Edge{from: ^from, to: ^to, kind: :invoke}] = g.edges
    end

    test "a traced send between two registered processes is a :message edge by name; the message itself never enters",
         %{
           collector: c
         } do
      parent = self()

      receiver =
        spawn_link(fn ->
          Process.register(self(), :tracer_test_receiver)
          send(parent, :registered)

          receive do
            _ -> send(parent, :got)
          end
        end)

      assert_receive :registered
      Process.register(self(), :tracer_test_sender)

      {:ok, _} = start(c, processes: [:tracer_test_sender])
      send(receiver, {:payload, @marker})
      assert_receive :got
      :ok = Tracer.stop()
      Process.unregister(:tracer_test_sender)

      {:ok, g} = Observed.snapshot(c)
      from = Node.id({:process, @server, :tracer_test_sender})
      to = Node.id({:process, @server, :tracer_test_receiver})
      assert Enum.any?(g.edges, &match?(%Edge{from: ^from, to: ^to, kind: :message}, &1))
      refute inspect(Observed.rows(c), limit: :infinity) =~ @marker
    end

    test "a send to an unregistered process is dropped, not written under a pid", %{collector: c} do
      Process.register(self(), :tracer_test_sender2)
      anon = spawn_link(fn -> receive do: (_ -> :ok) end)
      {:ok, _} = start(c, processes: [:tracer_test_sender2])
      send(anon, @marker)
      :ok = Tracer.stop()
      Process.unregister(:tracer_test_sender2)

      {:ok, g} = Observed.snapshot(c)
      refute Enum.any?(g.edges, &(&1.kind == :message))
      refute inspect(Observed.rows(c), limit: :infinity) =~ "#PID"
    end
  end
end
