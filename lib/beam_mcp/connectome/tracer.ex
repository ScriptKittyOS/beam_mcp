# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Connectome.Tracer do
  @moduledoc """
  A guarded tracer for the edges telemetry cannot see: a module calling a module, a process
  sending to a process. Off by default; opt-in; one at a time; hard limits; nothing left
  behind.

      {:ok, pid} = BeamMCP.Connectome.Tracer.start(
        collector: MyApp.Observed, server: "my-server",
        modules: [MyApp.Tools, MyApp.Backend], processes: [MyApp.Worker],
        max_messages: 1_000, max_duration_ms: 5_000)

  What it records, into the collector's table through `BeamMCP.Connectome.Observed.observe/5`:

  - a call into a traced module, as a module-level `:invoke` edge from the *caller's* module
    to the callee's -- `:erlang.trace_pattern/3` with a `{caller}` action and the `:arity`
    flag, so a trace message carries `{m, f, arity}` and never an argument. The caller is
    the frame the BEAM keeps: a call in tail position has no frame of its own, so it is
    attributed to the caller's caller (measured: `Alpha.run/1`'s tail call to `Beta` is
    filed under whoever called `Alpha`). A call whose caller the BEAM cannot name at all is
    counted against the message limit and not written;
  - a send from a traced process to a *registered* process, as a `:message` edge by
    registered name -- the message term is never read, and a send to an unregistered
    process is dropped rather than written under a pid. Names are resolved when the trace
    message is handled, not when the send happened: a process that exited or unregistered
    in between is dropped too. OTP's own registered processes -- the code server, a logger
    handler, telemetry's table owner -- are names like any other, so a traced process's
    sends to them are edges too; a host that wants only its own graph filters them.

  Calls are traced on every process in the node, the ones alive now and the ones spawned
  while the tracer runs. The BEAM discards a trace event whose tracer is the process that
  generated it, so the tracer never traces its own writes (measured).

  What it refuses: a second tracer while one runs (`{:error, :already_running}`); starting
  without a running collector (`{:error, :collector_not_started}`); a limit that is not a
  positive integer -- there is no unbounded mode; the wildcard `:_` or a module that cannot
  be loaded in `modules:`; a name in `processes:` that is not registered
  (`{:error, {:not_registered, name}}`); and a start that failed part-way, which clears what
  it had set and answers `{:error, {:init_failed, reason}}` -- a process already traced by
  someone else is the usual cause.

  **The limits, and what they bound.** `max_messages` counts trace messages as the tracer
  *handles* them; the BEAM queues them as they arrive, and under load the tracer is
  scheduled less often than the processes it traces. Two things keep that queue small: the
  tracer runs at high priority, and on every handled message it compares handled + queued
  against the limit and, the moment the sum reaches it, clears its patterns -- generation
  stops there, and the tracer exits after what was already queued. So the memory bound is
  the node-wide call rate into the named modules times the tracer's scheduling latency at
  high priority, not `max_messages` (measured: 64 hot callers against a limit of 1 000
  peaked at 12.8 million queued messages before these two measures, and at 140 000 after;
  with a limit too large to reach, 32 hot callers queued 3 million in a 100 ms window --
  the window times the rate is the bound, and the limit is what keeps the window short). `max_duration_ms` is enforced by a companion process that clears the
  patterns and flags at the deadline from outside the tracer's mailbox, so tracing stops on
  time even when the tracer is starved, and raises a flag the tracer reads before every
  write, so the tracer exits `{:shutdown, {:limit, :max_duration_ms, ms}}` on the next
  message it handles rather than after draining what was queued. `stop/0` clears the
  patterns and raises the same flag, for the same reason, then stops the tracer with a
  finite wait.

  **Nothing left behind, on every path.** The companion process monitors the tracer and
  clears the patterns and flags on any exit -- a kill included, which skips `terminate/2`.
  A pattern left set with no tracer would cost every call to that module a breakpoint and
  would feed a host's own later `:call` tracer with arguments (measured); that is what the
  companion exists to prevent. Patterns are global and unowned in the BEAM: clearing the
  patterns on a module clears any that someone else set on it too.

  Exits: `{:shutdown, {:limit, :max_messages, n}}`, `{:shutdown, {:limit, :max_duration_ms,
  ms}}`, `:normal` from `stop/0`, and `{:shutdown, :collector_gone}` when the collector
  dies under it. It never calls `:dbg`.
  """
  use GenServer

  alias BeamMCP.Connectome.Observed

  @name __MODULE__
  @defaults [max_messages: 1_000, max_duration_ms: 5_000, modules: [], processes: []]
  @stop_timeout 5_000
  # A one-word flag the tracer reads on every handled message, set from outside its
  # mailbox: 1 = the deadline passed, 2 = stop/0 was called. A message would queue behind
  # what is already there; the flag is read before the next write. Kept beside the module
  # list, so stop/0 can clear the patterns without asking a tracer that may be starved.
  @running {__MODULE__, :running}
  @deadline 1
  @stop 2

  @doc """
  Starts the one tracer. Options: `collector:` (the running collector's name, required),
  `server:` (the server identity string the edges are filed under, required), `modules:`
  (loaded modules whose calls are traced), `processes:` (registered names whose sends are
  traced), `max_messages:` (default 1_000), `max_duration_ms:` (default 5_000).
  """
  @spec start(keyword()) ::
          {:ok, pid()}
          | {:error,
             :already_running
             | :collector_not_started
             | {:invalid, atom(), term()}
             | {:not_registered, atom()}
             | {:init_failed, term()}}
  def start(opts) do
    opts = Keyword.merge(@defaults, opts)

    with :ok <- positive(opts, :max_messages),
         :ok <- positive(opts, :max_duration_ms),
         :ok <- modules(opts),
         :ok <- registered_names(opts),
         :ok <- server(opts),
         :ok <- collector_running(opts) do
      case GenServer.start(__MODULE__, opts, name: @name) do
        {:ok, pid} -> {:ok, pid}
        {:error, {:already_started, _}} -> {:error, :already_running}
        {:error, reason} -> {:error, {:init_failed, reason}}
      end
    end
  end

  @doc """
  Stops the tracer if one runs: the patterns and flags are cleared first, so tracing stops
  now rather than after the queue, then the process is stopped with a finite wait. `:ok`
  either way.
  """
  @spec stop() :: :ok
  def stop do
    case Process.whereis(@name) do
      nil ->
        :ok

      pid ->
        case :persistent_term.get(@running, nil) do
          {flag, modules} ->
            clear(modules)
            :atomics.put(flag, 1, @stop)

          nil ->
            :ok
        end

        GenServer.stop(pid, :normal, @stop_timeout)
    end
  catch
    :exit, _ -> :ok
  end

  @doc "Whether a tracer runs."
  @spec running?() :: boolean()
  def running?, do: Process.whereis(@name) != nil

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    Process.flag(:priority, :high)
    modules = Keyword.fetch!(opts, :modules)
    processes = Keyword.fetch!(opts, :processes)
    max_duration_ms = Keyword.fetch!(opts, :max_duration_ms)
    collector = Keyword.fetch!(opts, :collector)

    flag = :atomics.new(1, [])
    :persistent_term.put(@running, {flag, modules})

    # The companion is up before anything is set, so whatever this function sets is cleared
    # whatever happens next: it clears on the tracer's exit, kill included, and at the
    # deadline. It runs at high priority for the same reason the tracer does.
    companion = spawn_companion(self(), modules, max_duration_ms, flag)

    try do
      # The per-process flags first: a process already traced by someone else raises here,
      # and then nothing has been set yet.
      for p <- processes, do: :erlang.trace(Process.whereis(p), true, [:send, {:tracer, self()}])

      for m <- modules,
          do: :erlang.trace_pattern({m, :_, :_}, [{:_, [], [{:message, {:caller}}]}], [:local])

      # Calls are traced from every process, with the arity flag so no argument ever arrives.
      if modules != [], do: :erlang.trace(:all, true, [:call, :arity, {:tracer, self()}])
    rescue
      e ->
        clear(modules)
        send(companion, :cancel)
        reraise e, __STACKTRACE__
    end

    # The collector's death is a way out by name, not a badarg on the next traced call into
    # a table that is gone.
    _ = Process.monitor(:ets.info(collector, :owner))

    {:ok,
     %{
       collector: collector,
       server: Keyword.fetch!(opts, :server),
       modules: modules,
       processes: processes,
       max_messages: Keyword.fetch!(opts, :max_messages),
       max_duration_ms: max_duration_ms,
       seen: 0,
       companion: companion,
       flag: flag
     }}
  end

  @impl true
  def handle_info({:trace, _pid, :call, {m, _f, _arity}, {cm, _cf, _ca}}, state) do
    Observed.observe(
      state.collector,
      {:module, state.server, cm},
      {:module, state.server, m},
      :invoke
    )

    counted(state)
  end

  def handle_info({:trace, _pid, :call, _mfa, :undefined}, state), do: counted(state)

  def handle_info({:trace, from, :send, _message, to}, state) do
    # A send to the tracer itself (stop/0 is one) is the tracer's own business, not an edge.
    with false <- to == self() or to == @name,
         {:ok, from_name} <- registered(from),
         {:ok, to_name} <- registered(to) do
      Observed.observe(
        state.collector,
        {:process, state.server, from_name},
        {:process, state.server, to_name},
        :message
      )
    end

    counted(state)
  end

  # A send to a process that is gone arrives under its own tag; it is counted like any
  # other trace message and never written -- there is no name to write it under.
  def handle_info({:trace, _from, :send_to_non_existing_process, _message, _to}, state),
    do: counted(state)

  def handle_info(:max_duration, state) do
    {:stop, {:shutdown, {:limit, :max_duration_ms, state.max_duration_ms}}, state}
  end

  def handle_info({:DOWN, _ref, :process, _owner, _reason}, state) do
    {:stop, {:shutdown, :collector_gone}, state}
  end

  # Anything else is not a trace message.
  def handle_info(_other, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    clear(state.modules)
    send(state.companion, :cancel)
    :persistent_term.erase(@running)
    :ok
  end

  # On every handled message: the flag first -- a deadline or a stop/0 that could not reach
  # the front of the queue ends the drain here -- then handled plus queued against the
  # limit: the moment the sum reaches it, the patterns go, so generation stops here rather
  # than after the limit-th write.
  defp counted(%{seen: seen, max_messages: max, flag: flag} = state) do
    seen = seen + 1
    state = %{state | seen: seen}
    {:message_queue_len, queued} = Process.info(self(), :message_queue_len)

    case :atomics.get(flag, 1) do
      @deadline ->
        {:stop, {:shutdown, {:limit, :max_duration_ms, state.max_duration_ms}}, state}

      @stop ->
        {:stop, :normal, state}

      _ when seen + queued >= max ->
        clear(state.modules)
        {:stop, {:shutdown, {:limit, :max_messages, max}}, state}

      _ ->
        {:noreply, state}
    end
  end

  # Everything the tracer sets, unset: the pattern on every named module and the flags on
  # every process. Idempotent; run from the tracer, from stop/0, and from the companion at
  # the deadline.
  defp clear(modules) do
    clear_patterns(modules)
    :erlang.trace(:all, false, [:all])
    :ok
  end

  # After the tracer is dead only the patterns need clearing: the BEAM removes a tracer's
  # flags when the tracer exits, and clearing the flags of every process here would clear a
  # NEXT tracer's flags too, if one started in the gap (measured as a flake between tests).
  defp clear_patterns(modules) do
    for m <- modules, do: :erlang.trace_pattern({m, :_, :_}, false, [:local])
    :ok
  end

  # High priority, monitoring the tracer. At the deadline it clears and tells the tracer to
  # leave by name; on the tracer's exit for any reason it clears.
  defp spawn_companion(tracer, modules, max_duration_ms, flag) do
    spawn(fn ->
      Process.flag(:priority, :high)
      ref = Process.monitor(tracer)

      receive do
        :cancel ->
          :ok

        {:DOWN, ^ref, :process, ^tracer, _reason} ->
          clear_patterns(modules)
          :persistent_term.erase(@running)
      after
        max_duration_ms ->
          clear(modules)
          :atomics.put(flag, 1, @deadline)
          send(tracer, :max_duration)

          receive do
            {:DOWN, ^ref, :process, ^tracer, _reason} ->
              clear_patterns(modules)
              :persistent_term.erase(@running)

            :cancel ->
              :ok
          end
      end
    end)
  end

  defp registered(name) when is_atom(name), do: {:ok, name}

  defp registered(pid) when is_pid(pid) do
    case Process.info(pid, :registered_name) do
      {:registered_name, name} when is_atom(name) and name != [] -> {:ok, name}
      _ -> :error
    end
  end

  defp registered(_), do: :error

  defp positive(opts, key) do
    case Keyword.fetch!(opts, key) do
      n when is_integer(n) and n > 0 -> :ok
      other -> {:error, {:invalid, key, other}}
    end
  end

  # A loaded (or loadable) module, never the wildcard: `{:_, :_, :_}` would trace every
  # module in the node and, on stop, clear every local pattern in it, the host's included.
  defp modules(opts) do
    case Keyword.fetch!(opts, :modules) do
      list when is_list(list) ->
        if Enum.all?(list, &(is_atom(&1) and &1 != :_ and Code.ensure_loaded?(&1))),
          do: :ok,
          else: {:error, {:invalid, :modules, list}}

      other ->
        {:error, {:invalid, :modules, other}}
    end
  end

  defp registered_names(opts) do
    case Keyword.fetch!(opts, :processes) do
      list when is_list(list) ->
        cond do
          not Enum.all?(list, &is_atom/1) ->
            {:error, {:invalid, :processes, list}}

          missing = Enum.find(list, &(Process.whereis(&1) == nil)) ->
            {:error, {:not_registered, missing}}

          true ->
            :ok
        end

      other ->
        {:error, {:invalid, :processes, other}}
    end
  end

  defp server(opts) do
    case Keyword.get(opts, :server) do
      s when is_binary(s) -> :ok
      other -> {:error, {:invalid, :server, other}}
    end
  end

  defp collector_running(opts) do
    case Keyword.get(opts, :collector) do
      name when is_atom(name) and name != nil ->
        if :ets.whereis(name) == :undefined, do: {:error, :collector_not_started}, else: :ok

      _ ->
        {:error, :collector_not_started}
    end
  end
end
