# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Connectome.TracerTest do
  @moduledoc """
  The guarded tracer: opt-in, off by default, one at a time, stops itself at its limits,
  leaves nothing behind, and writes identity only -- a module-to-module `:invoke` from a
  traced call, a name-to-name `:message` from a traced send -- into the collector's table.

  The tests that forge the running term, forge a claim, or squat the tracer's registered
  name are ROBUSTNESS tests, not security tests: the tracer's threat model (its moduledoc)
  puts an adversary with code execution on the node out of scope. They stay because they
  keep `stop/0` and `start/1` total against a term of the wrong shape, which the in-scope
  stale-term-after-crash case needs, and they are cheap to run. No further guard of that
  kind is added on their account.
  """
  use ExUnit.Case, async: false

  alias BeamMCP.Connectome.{Canonical, Edge, Graph, Node, Observed, Tracer}
  alias BeamMCP.Fixture.Declared.{Alpha, Beta}
  alias BeamMCP.Fixture.Traced

  @marker "PAYLOAD-MARKER-1b2c3d"
  @server "srv"

  setup do
    # trace_info/2 on a function of a module not yet loaded says :undefined; load them first.
    # The tracer too: a lane found two tests failing whenever they were the first to touch
    # Tracer, because its autoload sent a message to the code server from the traced test
    # process, which consumed a one-shot tracer process the test had set up.
    for m <- [Alpha, Beta, Traced, Tracer, Observed], do: {:module, ^m} = Code.ensure_loaded(m)
    name = Module.concat(__MODULE__, :"c#{System.unique_integer([:positive])}")
    start_supervised!({Observed, name: name})
    on_exit(fn -> Tracer.stop() end)
    {:ok, collector: name}
  end

  defp start(collector, opts) do
    Tracer.start(Keyword.merge([collector: collector, server: @server], opts))
  end

  # A pid that is already gone, for a forged term's companion slot: a live one there is a
  # previous companion the next start waits on, which is pinned elsewhere.
  defp dead_pid do
    {pid, ref} = spawn_monitor(fn -> :ok end)
    receive do: ({:DOWN, ^ref, :process, ^pid, _} -> pid)
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

    test "the other options are refused by name too: modules and processes as atom lists, server as a string, collector as a name",
         %{collector: c} do
      assert {:error, {:invalid, :modules, [1]}} = start(c, modules: [1])
      assert {:error, {:invalid, :modules, :not_a_list}} = start(c, modules: :not_a_list)
      assert {:error, {:invalid, :processes, ["x"]}} = start(c, processes: ["x"])
      assert {:error, {:invalid, :processes, :x}} = start(c, processes: :x)
      assert {:error, {:invalid, :server, nil}} = Tracer.start(collector: c, modules: [Alpha])
      assert {:error, :collector_not_started} = Tracer.start(collector: "c", server: @server)
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

    test "the collector dying under it is a named way out, not a crash on the next message", %{
      collector: c
    } do
      # Found by a lane: the tracer kept running idle after the collector died and crashed
      # with a badarg on the next traced call. It watches the collector and leaves by name.
      {:ok, pid} = start(c, modules: [Beta])
      ref = Process.monitor(pid)
      :ok = stop_supervised!(c)
      assert_receive {:DOWN, ^ref, :process, ^pid, {:shutdown, :collector_gone}}, 2_000
      assert {:traced, false} = :erlang.trace_info({Beta, :run, 1}, :traced)
      refute Tracer.running?()
    end

    test "stop/0 is :ok even when the tracer dies under it -- the race with its own limit" do
      # A process under the tracer's name that exits for its own reason the moment it is
      # asked to stop, which is what a tracer hitting its limit during stop/0 looks like.
      pid = spawn(fn -> receive do: (_ -> exit(:limit_reached_first)) end)
      Process.register(pid, Tracer)
      assert :ok = Tracer.stop()
      refute Process.alive?(pid)
    end

    test "stop/0 is the third way out, and clears the same way", %{collector: c} do
      {:ok, _} = start(c, modules: [Alpha])
      assert {:traced, :local} = :erlang.trace_info({Alpha, :run, 1}, :traced)
      # While it runs, every process is call-traced WITH the arity flag: a trace message
      # carries {m, f, arity}, never the arguments.
      {:flags, flags} = :erlang.trace_info(self(), :flags)
      assert :call in flags and :arity in flags
      :ok = Tracer.stop()
      assert {:traced, false} = :erlang.trace_info({Alpha, :run, 1}, :traced)
      assert :ok = Tracer.stop()
    end
  end

  describe "under load, and under things that skip the orderly stop" do
    # Found by a lane that ran the tracer against sixty-four hot callers: max_messages
    # bounded what was HANDLED, the mailbox held 12.8 million trace messages (2.58 GB)
    # before the thousandth was handled; the duration timer, stop/0 and the collector's
    # DOWN all queued behind them; and two exit paths left the call patterns set with no
    # tracer -- feeding a host's later :call tracer with arguments.
    test "when more is queued than the limit allows, no more than the limit is written and the patterns are cleared",
         %{
           collector: c
         } do
      {:ok, pid} = start(c, modules: [Beta], max_messages: 10, max_duration_ms: 60_000)
      ref = Process.monitor(pid)
      :sys.suspend(pid)
      for _ <- 1..100, do: Traced.wrapped(1)
      :sys.resume(pid)

      assert_receive {:DOWN, ^ref, :process, ^pid, {:shutdown, {:limit, :max_messages, 10}}},
                     5_000

      # The hard bound: never more than the limit written, and the patterns gone. How many
      # fewer is best effort -- the queue-length read can miss what sits behind a pending
      # signal (measured: about one run in fifteen wrote the limit-th), so it is not asserted.
      {:ok, g} = Observed.snapshot(c)
      assert [%Edge{weight: w}] = g.edges
      assert w <= 10
      assert {:traced, false} = :erlang.trace_info({Beta, :run, 1}, :traced)
    end

    test "the duration limit stops tracing on time even when the tracer is not being scheduled, and the tracer leaves on the next message rather than draining the queue",
         %{collector: c} do
      {:ok, pid} = start(c, modules: [Beta], max_messages: 1_000_000, max_duration_ms: 50)
      ref = Process.monitor(pid)
      :sys.suspend(pid)
      # Queue work behind the deadline: these must not all be written before it leaves.
      for _ <- 1..500, do: Traced.wrapped(1)
      Process.sleep(150)
      # The tracer has not handled a thing; the patterns must be gone regardless.
      assert {:traced, false} = :erlang.trace_info({Beta, :run, 1}, :traced)
      :sys.resume(pid)

      assert_receive {:DOWN, ^ref, :process, ^pid, {:shutdown, {:limit, :max_duration_ms, 50}}},
                     5_000

      {:ok, g} = Observed.snapshot(c)
      # The flag is read before the write: nothing lands after it is raised, and the first
      # queued message ends the tracer without a row.
      assert g.edges == []
    end

    test "stop/0 ends the drain on the next message too, and is :ok", %{collector: c} do
      {:ok, pid} = start(c, modules: [Beta], max_messages: 1_000_000, max_duration_ms: 60_000)
      ref = Process.monitor(pid)
      # The raw suspend, not :sys.suspend/1: a sys-suspended GenServer still answers system
      # messages, and GenServer.stop is one, so it would leave before handling any message.
      true = :erlang.suspend_process(pid)
      for _ <- 1..500, do: Traced.wrapped(1)
      test = self()
      spawn(fn -> send(test, {:stopped, Tracer.stop()}) end)
      Process.sleep(50)
      assert {:traced, false} = :erlang.trace_info({Beta, :run, 1}, :traced)
      true = :erlang.resume_process(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5_000
      assert_receive {:stopped, :ok}, 5_000
      {:ok, g} = Observed.snapshot(c)
      # The flag is read before the write: nothing lands after it is raised, and the first
      # queued message ends the tracer without a row.
      assert g.edges == []
    end

    test "a kill after the deadline is cleared by the companion as well", %{collector: c} do
      {:ok, pid} = start(c, modules: [Beta], max_messages: 1_000_000, max_duration_ms: 50)
      :sys.suspend(pid)
      Process.sleep(100)
      Process.exit(pid, :kill)
      refute Process.alive?(pid)
      Process.sleep(50)
      assert {:traced, false} = :erlang.trace_info({Beta, :run, 1}, :traced)
    end

    test "a failed start leaves no pattern set and is a named refusal, not a raise", %{
      collector: c
    } do
      # A process already traced by someone else makes :erlang.trace/3 raise badarg; the
      # first tracer had set its call patterns before reaching that line and raised out of
      # start/1 with the patterns still set.
      other = spawn(fn -> receive do: (_ -> :ok) end)
      Process.register(self(), :tracer_test_owned)
      :erlang.trace(self(), true, [:send, {:tracer, other}])

      result = start(c, modules: [Beta], processes: [:tracer_test_owned])
      :erlang.trace(self(), false, [:all])
      Process.unregister(:tracer_test_owned)

      assert {:error, {:init_failed, _}} = result
      refute Tracer.running?()
      assert {:traced, false} = :erlang.trace_info({Beta, :run, 1}, :traced)
    end

    test "a kill leaves no pattern set: someone watches the tracer and clears what it set", %{
      collector: c
    } do
      {:ok, pid} = start(c, modules: [Beta])
      assert {:traced, :local} = :erlang.trace_info({Beta, :run, 1}, :traced)
      Process.exit(pid, :kill)
      refute Process.alive?(pid)

      assert Enum.any?(1..100, fn _ ->
               Process.sleep(10)
               :erlang.trace_info({Beta, :run, 1}, :traced) == {:traced, false}
             end)
    end

    test "the wildcard module is refused, and so is a module that cannot be loaded", %{
      collector: c
    } do
      # modules: [:_] set the node-wide pattern and then, on stop, wiped every local
      # pattern in the node, the host's own included.
      assert {:error, {:invalid, :modules, [:_]}} = start(c, modules: [:_])
      assert {:error, {:invalid, :modules, [NoSuch.Module]}} = start(c, modules: [NoSuch.Module])
    end

    test "a name in processes: that is not registered is refused, not silently traced as nothing",
         %{collector: c} do
      assert {:error, {:not_registered, :tracer_test_nobody}} =
               start(c, processes: [:tracer_test_nobody])
    end

    test "it never traces its own writes: the BEAM discards an event whose tracer is the generator",
         %{
           collector: c
         } do
      {:ok, pid} = start(c, modules: [Observed], max_messages: 20, max_duration_ms: 60_000)
      Traced.wrapped(1)
      Process.sleep(50)
      assert Tracer.running?()
      :ok = Tracer.stop()
      {:ok, g} = Observed.snapshot(c)
      tracer_id = Node.id({:module, @server, Tracer})
      refute Enum.any?(g.edges, &(&1.from == tracer_id))
      _ = pid
    end

    test "a receiver that unregistered between the send and the handling is dropped", %{
      collector: c
    } do
      parent = self()

      receiver =
        spawn_link(fn ->
          Process.register(self(), :tracer_test_fleeting)
          send(parent, :registered)
          receive do: (:go -> Process.unregister(:tracer_test_fleeting))
          receive do: (:done -> :ok)
        end)

      assert_receive :registered
      Process.register(self(), :tracer_test_sender5)
      {:ok, pid} = start(c, processes: [:tracer_test_sender5])
      :sys.suspend(pid)
      send(receiver, :go)
      Process.sleep(20)
      :sys.resume(pid)
      :ok = Tracer.stop()
      send(receiver, :done)
      Process.unregister(:tracer_test_sender5)
      {:ok, g} = Observed.snapshot(c)
      refute Enum.any?(g.edges, &(&1.to == Node.id({:process, @server, :tracer_test_fleeting})))
    end

    test "negative and float limits are refused like zero", %{collector: c} do
      assert {:error, {:invalid, :max_messages, -1}} = start(c, modules: [Beta], max_messages: -1)

      assert {:error, {:invalid, :max_duration_ms, 1.5}} =
               start(c, modules: [Beta], max_duration_ms: 1.5)
    end
  end

  describe "the companion, attacked" do
    # Round 2 of the safety lane: the companion's clear-and-erase after a kill raced the
    # next tracer's init (499 of 500 after a kill; 200 of 200 after a failed start), which
    # then ran with no running term and a queue-ordered stop/0; the companion was the sole
    # enforcer and nobody watched it; the node-wide flag clear wiped a host's own trace
    # flags; and the collector dying under a loaded tracer was still a badarg.
    test "a tracer started right after a kill owns the running term, and its stop/0 clears first",
         %{
           collector: c
         } do
      for _ <- 1..20 do
        {:ok, pid} = start(c, modules: [Beta], max_messages: 1_000_000)
        Process.exit(pid, :kill)
        refute Process.alive?(pid)
        {:ok, pid2} = start(c, modules: [Beta], max_messages: 1_000_000)
        assert {flag, [Beta], _} = :persistent_term.get({Tracer, :running}, nil)
        assert is_reference(flag)
        assert {:traced, :local} = :erlang.trace_info({Beta, :run, 1}, :traced)
        Process.sleep(5)
        # Still ours: the old companion's late clear did not take the pattern away.
        assert {:traced, :local} = :erlang.trace_info({Beta, :run, 1}, :traced)
        :ok = Tracer.stop()
        assert {:traced, false} = :erlang.trace_info({Beta, :run, 1}, :traced)
        assert :persistent_term.get({Tracer, :running}, nil) == nil
        _ = pid2
      end
    end

    test "a tracer started right after a failed start owns the running term", %{collector: c} do
      other = spawn(fn -> receive do: (_ -> :ok) end)
      Process.register(self(), :tracer_test_owned2)
      :erlang.trace(self(), true, [:send, {:tracer, other}])

      assert {:error, {:init_failed, _}} =
               start(c, modules: [Beta], processes: [:tracer_test_owned2])

      :erlang.trace(self(), false, [:all])
      Process.unregister(:tracer_test_owned2)

      {:ok, _} = start(c, modules: [Beta])
      assert {_, [Beta], _} = :persistent_term.get({Tracer, :running}, nil)
      Process.sleep(5)
      assert {:traced, :local} = :erlang.trace_info({Beta, :run, 1}, :traced)
      :ok = Tracer.stop()
      assert :persistent_term.get({Tracer, :running}, nil) == nil
    end

    test "the companion dying is a named way out, not a tracer with no deadline and no janitor",
         %{collector: c} do
      {:ok, pid} = start(c, modules: [Beta], max_duration_ms: 60_000)
      ref = Process.monitor(pid)
      {_, _, companion} = :persistent_term.get({Tracer, :running})
      Process.exit(companion, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid, {:shutdown, :companion_gone}}, 2_000
      assert {:traced, false} = :erlang.trace_info({Beta, :run, 1}, :traced)
      assert :persistent_term.get({Tracer, :running}, nil) == nil
    end

    test "stopping clears what the tracer set and nothing a host set: another tracer's flags on another process survive",
         %{
           collector: c
         } do
      host_tracer = spawn(fn -> receive do: (_ -> :ok) end)
      victim = spawn(fn -> receive do: (_ -> :ok) end)
      :erlang.trace(victim, true, [:procs, {:tracer, host_tracer}])

      {:ok, _} = start(c, modules: [Beta], max_duration_ms: 50)
      :ok = Tracer.stop()
      assert {:flags, [:procs]} = :erlang.trace_info(victim, :flags)

      {:ok, pid} = start(c, modules: [Beta], max_duration_ms: 50)
      ref = Process.monitor(pid)

      assert_receive {:DOWN, ^ref, :process, ^pid, {:shutdown, {:limit, :max_duration_ms, 50}}},
                     2_000

      assert {:flags, [:procs]} = :erlang.trace_info(victim, :flags)
      :erlang.trace(victim, false, [:all])
    end

    test "the collector dying under a loaded tracer is still the named way out", %{collector: c} do
      {:ok, pid} = start(c, modules: [Beta], max_messages: 1_000_000, max_duration_ms: 60_000)
      ref = Process.monitor(pid)
      true = :erlang.suspend_process(pid)
      for _ <- 1..200, do: Traced.wrapped(1)
      :ok = stop_supervised!(c)
      true = :erlang.resume_process(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, {:shutdown, :collector_gone}}, 5_000
    end

    test "a new tracer waits for a previous companion that is slow to die, but not forever", %{
      collector: c
    } do
      # A stale term naming a companion that never exits: the wait is bounded.
      slow = spawn(fn -> receive do: (:die -> :ok) end)
      :persistent_term.put({Tracer, :running}, {:atomics.new(1, []), [], slow})
      {t, {:ok, _}} = :timer.tc(fn -> start(c, modules: [Beta]) end)
      assert t >= 900_000 and t < 3_000_000
      send(slow, :die)
      :ok = Tracer.stop()
    end

    test "the companion's clear after a kill is only ever its own: a term already gone is left alone",
         %{
           collector: c
         } do
      {:ok, pid} = start(c, modules: [Beta])
      # Another tracer's term in place of this one's: the companion must leave it alone.
      foreign = {:atomics.new(1, []), [], self()}
      :persistent_term.put({Tracer, :running}, foreign)
      Process.exit(pid, :kill)
      Process.sleep(50)
      assert {:traced, false} = :erlang.trace_info({Beta, :run, 1}, :traced)
      assert :persistent_term.get({Tracer, :running}, nil) == foreign
      :persistent_term.erase({Tracer, :running})

      # And with no term at all in place, it still clears its own patterns.
      {:ok, pid} = start(c, modules: [Beta])
      :persistent_term.erase({Tracer, :running})
      Process.exit(pid, :kill)
      Process.sleep(50)
      assert {:traced, false} = :erlang.trace_info({Beta, :run, 1}, :traced)
    end

    test "the double-kill window: a companion killed and then its tracer leaves patterns, and the next start clears them, whatever modules it names",
         %{collector: c} do
      # Round 3 of the safety lane measured the page's mitigation false: a next tracer over
      # other modules left the old pattern set 200 times in 200. A start now clears what a
      # stale term names before it puts its own.
      {:ok, pid} = start(c, modules: [Beta])
      {_, _, companion} = :persistent_term.get({Tracer, :running})
      Process.exit(companion, :kill)
      Process.exit(pid, :kill)
      refute Process.alive?(pid)
      # Nobody cleared: the tracer never handled the companion's death.
      assert {:traced, :local} = :erlang.trace_info({Beta, :run, 1}, :traced)

      {:ok, _} = start(c, modules: [Alpha])
      assert {:traced, false} = :erlang.trace_info({Beta, :run, 1}, :traced)
      assert {_, [Alpha], _} = :persistent_term.get({Tracer, :running})
      :ok = Tracer.stop()
    end

    test "a companion that outlives the wait clears only what the new tracer did not claim", %{
      collector: c
    } do
      # A companion suspended from outside (a debugger) runs after the new tracer set its
      # own pattern on the same module; it must not take that pattern away.
      {:ok, pid} = start(c, modules: [Beta])
      {_, _, companion} = :persistent_term.get({Tracer, :running})
      true = :erlang.suspend_process(companion)
      Process.exit(pid, :kill)
      refute Process.alive?(pid)

      {t, {:ok, _}} = :timer.tc(fn -> start(c, modules: [Beta, Alpha]) end)
      assert t >= 900_000
      assert {:traced, :local} = :erlang.trace_info({Beta, :run, 1}, :traced)

      true = :erlang.resume_process(companion)
      Process.sleep(50)
      refute Process.alive?(companion)
      assert {:traced, :local} = :erlang.trace_info({Beta, :run, 1}, :traced)
      assert {:traced, :local} = :erlang.trace_info({Alpha, :run, 1}, :traced)
      assert {_, [Beta, Alpha], _} = :persistent_term.get({Tracer, :running})
      :ok = Tracer.stop()
      assert {:traced, false} = :erlang.trace_info({Beta, :run, 1}, :traced)
    end

    test "stop/0 with no tracer running clears what a stale term names and erases it", %{
      collector: c
    } do
      {:ok, pid} = start(c, modules: [Beta])
      {_, _, companion} = :persistent_term.get({Tracer, :running})
      Process.exit(companion, :kill)
      Process.exit(pid, :kill)
      refute Process.alive?(pid)
      assert {:traced, :local} = :erlang.trace_info({Beta, :run, 1}, :traced)
      assert :ok = Tracer.stop()
      assert {:traced, false} = :erlang.trace_info({Beta, :run, 1}, :traced)
      assert :persistent_term.get({Tracer, :running}, nil) == nil
    end

    test "a name reused during the run is not the tracer's to clear: a host's own flags on the new holder survive stop/0 and the deadline",
         %{collector: c} do
      # Found by the safety lane: the flags were cleared by NAME at clear time, so a process
      # that took a named process's name after it died lost the host's own :send trace,
      # silently, on both exit paths.
      host_tracer = spawn_link(fn -> Process.sleep(:infinity) end)

      for exit_path <- [:stop, :deadline] do
        holder1 = spawn(fn -> receive do: (_ -> :ok) end)
        Process.register(holder1, :tracer_test_reused)

        {:ok, pid} =
          start(c,
            modules: [],
            processes: [:tracer_test_reused],
            max_duration_ms: if(exit_path == :deadline, do: 100, else: 60_000)
          )

        ref = Process.monitor(pid)
        ref1 = Process.monitor(holder1)
        send(holder1, :die)
        assert_receive {:DOWN, ^ref1, :process, ^holder1, _}
        holder2 = spawn(fn -> receive do: (_ -> :ok) end)
        Process.register(holder2, :tracer_test_reused)
        :erlang.trace(holder2, true, [:send, :receive, {:tracer, host_tracer}])

        case exit_path do
          :stop ->
            assert :ok = Tracer.stop()
            assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5_000

          :deadline ->
            assert_receive {:DOWN, ^ref, :process, ^pid,
                            {:shutdown, {:limit, :max_duration_ms, 100}}},
                           5_000
        end

        {:flags, flags} = :erlang.trace_info(holder2, :flags)
        assert Enum.sort(flags) == [:receive, :send]
        assert {:tracer, ^host_tracer} = :erlang.trace_info(holder2, :tracer)
        :erlang.trace(holder2, false, [:all])
        ref2 = Process.monitor(holder2)
        send(holder2, :die)
        assert_receive {:DOWN, ^ref2, :process, ^holder2, _}
      end
    end

    test "a named process the host re-traced under its own tracer keeps that flag: only this tracer's flag is cleared",
         %{collector: c} do
      # A host tracer that outlives every trace message it is sent: a one-shot receiver
      # would exit on the first traced send and the BEAM would remove its flags itself.
      host_tracer = spawn_link(fn -> Process.sleep(:infinity) end)
      Process.register(self(), :tracer_test_retraced)
      {:ok, pid} = start(c, modules: [], processes: [:tracer_test_retraced])
      assert {:tracer, ^pid} = :erlang.trace_info(self(), :tracer)

      # The host takes the process over: flags are global, and it may.
      :erlang.trace(self(), false, [:all])
      :erlang.trace(self(), true, [:send, {:tracer, host_tracer}])

      assert :ok = Tracer.stop()
      assert {:flags, [:send]} = :erlang.trace_info(self(), :flags)
      assert {:tracer, ^host_tracer} = :erlang.trace_info(self(), :tracer)
      :erlang.trace(self(), false, [:all])
      Process.unregister(:tracer_test_retraced)
    end

    # ROBUSTNESS, not security -- this test and the six after it forge the term, forge a
    # claim, or squat the name; see the moduledoc.
    test "stop/0 reads the tracer's own claim, not the public term: under a forged term it still clears first and ends on the next message",
         %{collector: c} do
      # Measured by the safety lane: with a term that was not the tracer's, stop/0 had no
      # flag and no modules to clear and queued behind everything -- 9 million rows
      # written after the call, :ok at 5 s with the tracer alive and its pattern set.
      {:ok, pid} = start(c, modules: [Beta], max_messages: 1_000_000, max_duration_ms: 60_000)
      ref = Process.monitor(pid)
      true = :erlang.suspend_process(pid)
      for _ <- 1..500, do: Traced.wrapped(1)
      :persistent_term.put({Tracer, :running}, {:atomics.new(1, []), @marker, dead_pid()})
      test = self()
      spawn(fn -> send(test, {:stopped, Tracer.stop()}) end)
      Process.sleep(50)
      assert {:traced, false} = :erlang.trace_info({Beta, :run, 1}, :traced)
      true = :erlang.resume_process(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 5_000
      assert_receive {:stopped, :ok}, 5_000
      {:ok, g} = Observed.snapshot(c)
      # The flag is read before the write: nothing lands after it is raised, and the first
      # queued message ends the tracer without a row.
      assert g.edges == []
      assert :persistent_term.get({Tracer, :running}, nil) == nil
    end

    test "a claim is honoured only from a tracer that is running: a forged well-shaped term does not keep a killed tracer's patterns set",
         %{collector: c} do
      # Measured by the safety lane: the companion took any well-shaped term whose flag was
      # not its own as a newer tracer's claim, and a forged one naming its own modules
      # left the killed tracer's pattern set with no tracer behind it.
      {:ok, pid} = start(c, modules: [Beta])
      {_, _, companion} = :persistent_term.get({Tracer, :running})
      forged = {:atomics.new(1, []), [Beta], dead_pid()}
      :persistent_term.put({Tracer, :running}, forged)
      Process.exit(pid, :kill)
      Process.sleep(50)
      refute Process.alive?(companion)
      assert {:traced, false} = :erlang.trace_info({Beta, :run, 1}, :traced)
      # Not its own: left for the next start or stop, which erase it.
      assert :persistent_term.get({Tracer, :running}, nil) == forged
      assert :ok = Tracer.stop()
      assert :persistent_term.get({Tracer, :running}, nil) == nil
    end

    test "a claim of another shape is no claim: a squatter under the tracer's name cannot make stop/0 raise or clear what it names",
         %{collector: _} do
      # Found by the safety lane: the claim was read from whatever process held the name,
      # with none of the shape check the public term gets. A process registered under the
      # name already refuses every start; it must not turn stop/0 into a raise either.
      :erlang.trace_pattern({Beta, :_, :_}, true, [:local])
      assert {:traced, :local} = :erlang.trace_info({Beta, :run, 1}, :traced)

      for crafted <- [
            {:atomics.new(1, []), ["not", :atoms], []},
            {:atomics.new(1, []), @marker, []},
            {:not_a_reference, [Beta], []}
          ] do
        test = self()

        squatter =
          spawn(fn ->
            Process.put({Tracer, :claim}, crafted)
            send(test, :claimed)
            receive do: (_ -> exit(:squatted))
          end)

        assert_receive :claimed
        Process.register(squatter, Tracer)
        ref = Process.monitor(squatter)
        assert :ok = Tracer.stop()
        assert_receive {:DOWN, ^ref, :process, ^squatter, :squatted}
        # The host's own pattern on a module the crafted claim named is not the squatter's.
        assert {:traced, :local} = :erlang.trace_info({Beta, :run, 1}, :traced)
      end

      :erlang.trace_pattern({Beta, :_, :_}, false, [:local])
    end

    test "a squatter with no claim is no claim to the companion either: after a kill it clears everything its tracer set",
         %{collector: c} do
      {:ok, pid} = start(c, modules: [Beta])
      {_, _, companion} = :persistent_term.get({Tracer, :running})
      true = :erlang.suspend_process(companion)
      ref = Process.monitor(pid)
      Process.exit(pid, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}
      assert {:traced, :local} = :erlang.trace_info({Beta, :run, 1}, :traced)

      squatter = spawn(fn -> receive do: (_ -> exit(:squatted)) end)
      Process.register(squatter, Tracer)
      true = :erlang.resume_process(companion)
      Process.sleep(50)
      refute Process.alive?(companion)
      assert {:traced, false} = :erlang.trace_info({Beta, :run, 1}, :traced)
      assert :persistent_term.get({Tracer, :running}, nil) == nil
      assert :ok = Tracer.stop()
      refute Process.alive?(squatter)
    end

    test "a running term of another shape is nobody's: stop/0 with no tracer erases it and answers :ok, and the next start proceeds",
         %{collector: c} do
      # The term is public and unowned. A lane forged it in six shapes and every one made
      # stop/0 raise into its caller and left the term, so no later start could succeed.
      ref = :atomics.new(1, [])
      dead = dead_pid()

      for forged <- [
            @marker,
            {ref, @marker, dead},
            {ref, [@marker], dead},
            {ref, [Beta]},
            {ref, [Beta], dead, :extra},
            {ref, [Beta | Beta], dead},
            {:not_a_reference, [Beta], dead}
          ] do
        :persistent_term.put({Tracer, :running}, forged)
        assert :ok = Tracer.stop()
        assert :persistent_term.get({Tracer, :running}, nil) == nil

        :persistent_term.put({Tracer, :running}, forged)
        assert {:ok, _} = start(c, modules: [Beta])
        assert {_, [Beta], _} = :persistent_term.get({Tracer, :running})
        assert :ok = Tracer.stop()
      end
    end

    test "a term forged while the tracer runs does not keep it alive: stop/0 stops it, and its own exit clears",
         %{collector: c} do
      # With a non-atomics flag in the term, stop/0 cleared the patterns and then raised on
      # the flag, leaving the tracer alive; with a non-list module field it raised before
      # anything was cleared.
      dead = dead_pid()

      for forged <- [{:not_a_reference, [Beta], dead}, {:atomics.new(1, []), @marker, dead}] do
        {:ok, pid} = start(c, modules: [Beta])
        :persistent_term.put({Tracer, :running}, forged)
        assert :ok = Tracer.stop()
        refute Process.alive?(pid)
        assert {:traced, false} = :erlang.trace_info({Beta, :run, 1}, :traced)
        assert :persistent_term.get({Tracer, :running}, nil) == nil
      end
    end

    test "the companion clears its own patterns after a kill whatever shape the term in place has",
         %{collector: c} do
      # A forged non-list module field made `modules -- claimed` raise in the companion:
      # it died with the patterns set, and neither start/1 nor stop/0 could take them away.
      {:ok, pid} = start(c, modules: [Beta])
      {_, _, companion} = :persistent_term.get({Tracer, :running})
      :persistent_term.put({Tracer, :running}, {:atomics.new(1, []), @marker, dead_pid()})
      Process.exit(pid, :kill)
      Process.sleep(50)
      refute Process.alive?(companion)
      assert {:traced, false} = :erlang.trace_info({Beta, :run, 1}, :traced)

      assert {:ok, _} = start(c, modules: [Alpha])
      assert {_, [Alpha], _} = :persistent_term.get({Tracer, :running})
      :ok = Tracer.stop()
    end

    test "a registered name is identity: a secret in a name is published in the bytes, the message beside it is not",
         %{collector: c} do
      test = self()
      name = :"#{@marker}-receiver"
      receiver = spawn_link(fn -> receive do: (m -> send(test, {:got, m})) end)
      Process.register(receiver, name)
      Process.register(self(), :tracer_test_sender)

      {:ok, tracer} = start(c, modules: [], processes: [:tracer_test_sender])
      send(name, {:secret, "the-message-#{@marker}"})
      assert_receive {:got, {:secret, _}}
      _ = :sys.get_state(tracer)
      :ok = Tracer.stop()
      Process.unregister(:tracer_test_sender)

      {:ok, graph} = Observed.snapshot(c)
      {:ok, bytes} = Canonical.encode(graph)
      assert bytes =~ Atom.to_string(name)
      refute bytes =~ "the-message-"
      refute inspect(Observed.rows(c), printable_limit: :infinity) =~ "the-message-"
    end

    test "a process a host already traces is skipped by the call trace, silently: its calls are no edges and its flags stay the host's",
         %{collector: c} do
      # A consumer lane measured it: the BEAM refuses a second tracer on a process without
      # a log line on this path; the log the page once promised never came.
      host_tracer = spawn_link(fn -> Process.sleep(:infinity) end)
      test = self()

      host_traced =
        spawn_link(fn ->
          receive do
            :call ->
              Beta.run(1)
              send(test, :called)
              Process.sleep(:infinity)
          end
        end)

      :erlang.trace(host_traced, true, [:call, {:tracer, host_tracer}])
      {:ok, tracer} = start(c, modules: [Beta])
      send(host_traced, :call)
      assert_receive :called
      Beta.run(1)
      _ = :sys.get_state(tracer)
      :ok = Tracer.stop()

      {:ok, g} = Observed.snapshot(c)
      assert [%Edge{weight: 1}] = g.edges
      assert {:tracer, ^host_tracer} = :erlang.trace_info(host_traced, :tracer)
      assert {:flags, [:call]} = :erlang.trace_info(host_traced, :flags)
      :erlang.trace(host_traced, false, [:all])
    end

    @tag :hot_reload
    test "a hot reload of the tracer's module ends a running trace by name: the companion is old code, and its purge is the companion dying",
         %{collector: c} do
      # The moduledoc says so; a consumer lane ran it for three rounds. Pinned here.
      {:ok, pid} = start(c, modules: [Beta])
      ref = Process.monitor(pid)
      Beta.run(1)
      _ = :sys.get_state(pid)

      :code.purge(Tracer)
      {:module, Tracer} = :code.load_file(Tracer)
      :code.purge(Tracer)

      assert_receive {:DOWN, ^ref, :process, ^pid, {:shutdown, :companion_gone}}, 2_000
      assert {:traced, false} = :erlang.trace_info({Beta, :run, 1}, :traced)
      assert :persistent_term.get({Tracer, :running}, nil) == nil
      refute Tracer.running?()
      assert {:ok, _} = start(c, modules: [Beta])
      :ok = Tracer.stop()
    end

    test "the tracer runs at high priority, and a host's pattern on a traced module is cleared with the tracer's",
         %{
           collector: c
         } do
      {:ok, pid} = start(c, modules: [Beta])
      assert {:priority, :high} = Process.info(pid, :priority)
      :ok = Tracer.stop()

      # Patterns are global and unowned: the page says a host's own pattern on a module the
      # tracer named goes with the tracer's.
      :erlang.trace_pattern({Beta, :_, :_}, true, [:local])
      assert {:traced, :local} = :erlang.trace_info({Beta, :run, 1}, :traced)
      {:ok, _} = start(c, modules: [Beta])
      :ok = Tracer.stop()
      assert {:traced, false} = :erlang.trace_info({Beta, :run, 1}, :traced)
    end

    test "after a kill and its clear, a host's own later call tracer sees nothing for the old modules",
         %{
           collector: c
         } do
      {:ok, pid} = start(c, modules: [Beta])
      Process.exit(pid, :kill)
      Process.sleep(50)
      assert {:traced, false} = :erlang.trace_info({Beta, :run, 1}, :traced)

      test = self()
      host_tracer = spawn(fn -> receive do: (m -> send(test, {:host_saw, m})) end)
      :erlang.trace(self(), true, [:call, {:tracer, host_tracer}])
      Beta.run(:marker)
      :erlang.trace(self(), false, [:all])
      refute_receive {:host_saw, _}, 100
    end

    test "a traced process's sends to one of OTP's own registered processes are edges too", %{
      collector: c
    } do
      Process.register(self(), :tracer_test_sender6)
      {:ok, _} = start(c, processes: [:tracer_test_sender6])
      # A call that is a message to the code server from this process, whether or not the
      # module is already loaded (under cover every module is).
      _ = :code.get_path()
      _ = :sys.get_state(Tracer)
      :ok = Tracer.stop()
      Process.unregister(:tracer_test_sender6)
      {:ok, g} = Observed.snapshot(c)
      code_server = Node.id({:process, @server, :code_server})
      assert Enum.any?(g.edges, &(&1.to == code_server and &1.kind == :message))
    end
  end

  describe "what it writes" do
    test "a traced call is a module-level :invoke edge from the caller's module to the callee's, and nothing of the arguments",
         %{
           collector: c
         } do
      {:ok, _} = start(c, modules: [Beta])
      Traced.wrapped(@marker)
      # The barrier: a stop ends the tracer on the next message it handles, writing nothing
      # after the flag, so the trace message must be handled before the stop is asked.
      _ = :sys.get_state(Tracer)
      :ok = Tracer.stop()

      {:ok, %Graph{} = g} = Observed.snapshot(c)
      from = Node.id({:module, @server, Traced})
      to = Node.id({:module, @server, Beta})

      assert [%Edge{from: ^from, to: ^to, kind: :invoke, provenance: :observed, sign: :unset}] =
               g.edges

      assert Enum.all?(g.nodes, &(&1.kind == :module and &1.level == :module))
      refute inspect(Observed.rows(c), limit: :infinity) =~ @marker
    end

    test "a dynamic call through apply/3 is the same edge as a static one", %{collector: c} do
      {:ok, _} = start(c, modules: [Beta])
      Traced.apply_wrapped(Beta, [@marker])
      _ = :sys.get_state(Tracer)
      :ok = Tracer.stop()

      {:ok, g} = Observed.snapshot(c)
      from = Node.id({:module, @server, Traced})
      to = Node.id({:module, @server, Beta})
      assert [%Edge{from: ^from, to: ^to, kind: :invoke}] = g.edges
    end

    test "a call in tail position is attributed to the caller's caller: the frame the BEAM keeps",
         %{
           collector: c
         } do
      # Measured before it was written: Alpha.run/1's call to Beta is a tail call, and the
      # caller action names whoever called Alpha. Stated in the moduledoc as the bound it is.
      {:ok, _} = start(c, modules: [Beta])
      Traced.tail(1)
      Alpha.run(1)
      _ = :sys.get_state(Tracer)
      :ok = Tracer.stop()

      {:ok, g} = Observed.snapshot(c)
      here = Node.id({:module, @server, __MODULE__})
      to = Node.id({:module, @server, Beta})
      assert [%Edge{from: ^here, to: ^to, kind: :invoke, weight: 2}] = g.edges
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

          for _ <- 1..2 do
            receive do
              _ -> send(parent, :got)
            end
          end

          # Stay registered until the tracer has handled the trace messages: it resolves
          # names when it handles them, not when the send happened.
          receive do
            :done -> :ok
          end
        end)

      assert_receive :registered
      Process.register(self(), :tracer_test_sender)

      {:ok, _} = start(c, processes: [:tracer_test_sender])
      # Once by pid, once by registered name: the same edge, weight two.
      send(receiver, {:payload, @marker})
      send(:tracer_test_receiver, {:payload, @marker})
      assert_receive :got
      assert_receive :got
      # stop/0 ends the tracer on the next message it handles and discards what is still
      # queued; a system message is answered in mailbox order, so this waits for both.
      _ = :sys.get_state(Tracer)
      :ok = Tracer.stop()
      send(receiver, :done)
      Process.unregister(:tracer_test_sender)

      {:ok, g} = Observed.snapshot(c)
      from = Node.id({:process, @server, :tracer_test_sender})
      to = Node.id({:process, @server, :tracer_test_receiver})

      assert Enum.any?(
               g.edges,
               &match?(%Edge{from: ^from, to: ^to, kind: :message, weight: 2}, &1)
             )

      refute inspect(Observed.rows(c), limit: :infinity) =~ @marker
    end

    test "a call whose caller the BEAM cannot name -- a process's first call -- is counted and not written",
         %{
           collector: c
         } do
      # Measured before it was written: spawn(Beta, :run, [1]) reports the caller as
      # :undefined. It counts against the limit; it is not an edge from nowhere.
      {:ok, pid} = start(c, modules: [Beta], max_messages: 1)
      ref = Process.monitor(pid)
      spawn(Beta, :run, [1])
      assert_receive {:DOWN, ^ref, :process, ^pid, {:shutdown, {:limit, :max_messages, 1}}}, 2_000
      assert {:ok, %Graph{edges: []}} = Observed.snapshot(c)
    end

    test "a send to a dead process counts against the limit like any other trace message", %{
      collector: c
    } do
      # An adversarial read sent fifty messages to a dead pid against a limit of ten and the
      # tracer stayed up: that trace shape is :send_to_non_existing_process, and it fell to
      # the ignore clause, uncounted. The message term is still never read.
      Process.register(self(), :tracer_test_sender4)
      dead = spawn(fn -> :ok end)
      ref = Process.monitor(dead)
      assert_receive {:DOWN, ^ref, :process, ^dead, _}
      {:ok, pid} = start(c, processes: [:tracer_test_sender4], max_messages: 10)
      ref = Process.monitor(pid)
      for _ <- 1..50, do: send(dead, @marker)

      assert_receive {:DOWN, ^ref, :process, ^pid, {:shutdown, {:limit, :max_messages, 10}}},
                     2_000

      Process.unregister(:tracer_test_sender4)
      refute inspect(Observed.rows(c), limit: :infinity) =~ @marker
    end

    test "a message the tracer does not understand is ignored, and a send addressed by {name, node} is dropped",
         %{
           collector: c
         } do
      Process.register(self(), :tracer_test_sender3)
      {:ok, pid} = start(c, processes: [:tracer_test_sender3])
      send(pid, :something_else)
      send({:tracer_test_sender3, node()}, :to_myself_by_name)
      assert Tracer.running?()
      _ = :sys.get_state(Tracer)
      :ok = Tracer.stop()
      Process.unregister(:tracer_test_sender3)

      # The test process may have sent to a registered system process while traced (the
      # code server, loading a module lazily -- seen under one seed); what must be absent
      # is an edge to itself under its own name, which the {name, node} send would have been.
      {:ok, g} = Observed.snapshot(c)
      me = Node.id({:process, @server, :tracer_test_sender3})
      refute Enum.any?(g.edges, &(&1.to == me))
    end

    test "a send to an unregistered process is dropped, not written under a pid", %{collector: c} do
      Process.register(self(), :tracer_test_sender2)
      anon = spawn_link(fn -> receive do: (_ -> :ok) end)
      {:ok, _} = start(c, processes: [:tracer_test_sender2])
      send(anon, @marker)
      _ = :sys.get_state(Tracer)
      :ok = Tracer.stop()
      Process.unregister(:tracer_test_sender2)

      # The test process may send to registered system processes while traced (the gate's
      # run showed one); those are name-to-name edges and legitimate. What must not appear
      # is anything derived from a pid.
      {:ok, g} = Observed.snapshot(c)
      refute inspect(Observed.rows(c), limit: :infinity) =~ "#PID"
      refute inspect(g, limit: :infinity) =~ "#PID"

      for %Edge{kind: :message, from: from, to: to} <- g.edges do
        assert String.starts_with?(from, "srv/process/")
        assert String.starts_with?(to, "srv/process/")
      end
    end
  end
end
