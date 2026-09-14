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
  while the tracer runs -- except one a host already traces under its own tracer, which
  the BEAM skips (one tracer per process) and logs once; its calls are no edges. The BEAM discards a trace event whose tracer is the process that
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
  tracer runs at high priority, and on the first and every 32nd handled message it compares
  handled + queued against the limit and, the moment the sum reaches it, clears its
  patterns -- generation stops there, and the tracer exits on the next message it handles;
  what was queued behind it is discarded. So the memory bound is
  the node-wide call rate into the named modules times the tracer's scheduling latency at
  high priority, not `max_messages` (measured: 64 hot callers against a limit of 1 000
  peaked at 12.8 million queued messages before these two measures, and from some tens
  of thousands to a hundred-odd thousand after, run to run; with a limit too large to reach, 32 hot callers
  queued some millions in a 100 ms window -- the window times the rate is the bound, and
  the limit is what keeps the window short). The mailbox is kept off-heap, so a large
  queue is not copied at every collection while it drains (measured: on-heap, a drain
  under continuous arrival fell to 191 µs per message). `max_duration_ms` is enforced by a companion process that clears the
  patterns and flags at the deadline from outside the tracer's mailbox, so tracing stops on
  time even when the tracer is starved, and raises a flag the tracer reads on every
  message it handles, so the tracer exits `{:shutdown, {:limit, :max_duration_ms, ms}}` on
  the next message it handles rather than after draining what was queued -- the read
  follows that message's write, so at most one row lands after the flag is raised.
  `stop/0` clears the patterns and raises the same flag, for the same reason, then stops
  the tracer with a finite wait of five seconds. `stop/0` reads the tracer's own claim
  -- flag, modules, the named pids, in its process dictionary -- never the public running
  term, which anyone can write (measured: under a forged term a stop had no flag to raise
  and queued behind nine million rows); the companion holds the same claim in its closure
  from the start. A claim of another shape, put there by a process that took the name, is
  no claim (measured: it had made `stop/0` raise).

  **Nothing left behind, on every path but one.** The companion process monitors the tracer
  and clears the patterns on any exit -- a kill included, which skips `terminate/2`; the BEAM
  removes a dead tracer's flags itself. A pattern left set with no tracer would cost every
  call to that module a breakpoint and would feed a host's own later `:call` tracer with
  arguments (measured); that is what the companion exists to prevent. The tracer watches
  the companion back and leaves `{:shutdown, :companion_gone}` if it dies, since it is the
  only enforcer of the deadline and of the clear-on-kill; a hot reload of this module
  purges the companion, an anonymous function of the old code, and ends a running trace
  that way (measured), and `:code.soft_purge/1` refuses while a trace runs, for the same
  reason. The one path that leaves patterns set: the companion killed, then the tracer
  killed before it handles that death -- the next `start/1`, whatever modules it names,
  and `stop/0` both clear what the stale term names (measured). A new tracer waits for a
  previous
  companion to finish before it starts (measured: without that, the old companion's late
  erase landed on the new tracer's running term 499 times in 500). Patterns are global and
  unowned in the BEAM: clearing the patterns on a module clears any that someone else set
  on it too. Nothing is cleared that the tracer did not set: only its patterns and the send
  flag on the processes it named, resolved to pids once at start and cleared only where
  this tracer's is the flag on them -- a name reused during the run belongs to another
  process, and a process a host re-traced under its own tracer keeps that (measured: cleared
  by name at clear time, a new holder lost the host's own send trace on both exit paths);
  a node-wide flag clear would wipe a host's own trace flags on unrelated processes
  (measured). What a stale running term names is cleared by the next `start/1` or
  `stop/0`, a host's own modules included if someone put them there.

  Exits: `{:shutdown, {:limit, :max_messages, n}}`, `{:shutdown, {:limit, :max_duration_ms,
  ms}}`, `:normal` from `stop/0`, `{:shutdown, :collector_gone}` when the collector dies
  under it -- met as its DOWN or as the first write into the table that is gone, whichever
  comes first in the queue -- and `{:shutdown, :companion_gone}`. It never calls `:dbg`.

  **The threat model, which is the boundary of every claim above.** In scope: accident and
  failure on a node running only code the host put there -- crashes, kills, restarts and the
  host's supervisor, a registered name reused by an unrelated process, a host tracing its
  own processes, hot reload, starvation under load, the public API called wrongly or in the
  wrong order, and a stale running term left by a previous crash of this module. Out of
  scope: an adversary executing code inside the same node -- a process that registers
  itself under this module's name, a forged persistent term, a crafted process dictionary.
  Such an adversary can already read the collector's table directly, call the host's
  dispatch function, replace a module with `:code.load_binary/3`, or trace every process
  itself; this tracer is not a security boundary against it, and nothing in this package
  makes it one. The shape guards on the running term and on the claim are robustness --
  they keep `stop/0` and `start/1` total against a term of the wrong shape, which the
  stale-term-after-crash case needs -- not a defence.
  """
  use GenServer

  alias BeamMCP.Connectome.Observed

  @name __MODULE__
  @defaults [max_messages: 1_000, max_duration_ms: 5_000, modules: [], processes: []]
  @stop_timeout 5_000
  @await_companion 1_000
  # The tracer's own claim -- flag, modules, the named pids -- in its process dictionary,
  # which nothing outside the tracer can write. `stop/0` and the companion read it there;
  # the public term is read only when no tracer runs.
  @claim {__MODULE__, :claim}
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
        stop_stale()

      pid ->
        # The tracer's own claim, not the public term: under a forged term this had no
        # flag to raise and no modules to clear, and queued behind everything (measured:
        # nine million rows written after the call). The dictionary read is not
        # queue-ordered (measured: 16 µs on a suspended tracer with a million queued).
        case claim(pid) do
          {flag, modules, _pids} ->
            clear_patterns(modules)
            :atomics.put(flag, 1, @stop)

          nil ->
            :ok
        end

        GenServer.stop(pid, :normal, @stop_timeout)
    end
  catch
    :exit, _ -> :ok
  end

  # No tracer, but a term: the double-kill window left it. Clear what it names, erase it.
  # A term of another shape is nobody's and names nothing to clear; it is erased so the
  # next start is not refused by it (measured: a lane forged six shapes, each of which had
  # raised out of here and stayed).
  defp stop_stale do
    case running_term() do
      {_flag, modules, _companion} ->
        clear_patterns(modules)
        _ = :persistent_term.erase(@running)
        :ok

      nil ->
        :ok

      :malformed ->
        _ = :persistent_term.erase(@running)
        :ok
    end
  end

  # The term is public and unowned, so only its own shape is trusted: a three-tuple whose
  # modules are a proper list of atoms -- what `trace_pattern/3` would raise on otherwise.
  # Anything else is `:malformed`. The flag in it is never dereferenced: a live tracer's
  # flag is read from its own claim, and the companion holds its own.
  defp running_term do
    case :persistent_term.get(@running, nil) do
      {_flag, modules, _companion} = term ->
        if atoms?(modules), do: term, else: :malformed

      nil ->
        nil

      _ ->
        :malformed
    end
  end

  # No claim, whether the process is gone (`Process.info/2` answers nil for a dead pid --
  # the tracer left between the whereis and this read), has none, or holds one of another
  # shape: the same answer. The name can be taken by any process, and one that squats it
  # with a crafted claim already refuses every start; it must not turn `stop/0` into a
  # raise, or name a host's modules for clearing (measured, by a lane).
  defp claim(pid) do
    with {:dictionary, dictionary} <- Process.info(pid, :dictionary),
         {@claim, {flag, modules, _pids} = claim} <- List.keyfind(dictionary, @claim, 0),
         true <- is_reference(flag) and atoms?(modules) do
      claim
    else
      _ -> nil
    end
  end

  defp atoms?([m | rest]) when is_atom(m), do: atoms?(rest)
  defp atoms?([]), do: true
  defp atoms?(_), do: false

  @doc "Whether a tracer runs."
  @spec running?() :: boolean()
  def running?, do: Process.whereis(@name) != nil

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    Process.flag(:priority, :high)
    Process.flag(:message_queue_data, :off_heap)
    modules = Keyword.fetch!(opts, :modules)
    processes = Keyword.fetch!(opts, :processes)
    max_duration_ms = Keyword.fetch!(opts, :max_duration_ms)
    collector = Keyword.fetch!(opts, :collector)

    # A previous tracer's companion may still be clearing after a kill or a failed start;
    # its erase would land on this tracer's term (measured: 499 of 500 starts after a kill).
    # Wait for it to be gone before anything is put. A term still there afterwards belongs
    # to a dead tracer -- a live one would have refused this name -- and whatever it names
    # is cleared here: the double-kill window leaves patterns, and the next start is what
    # takes them away (measured: a start over other modules had left them, 200 of 200).
    await_previous_companion()
    stop_stale()

    flag = :atomics.new(1, [])
    # The named processes are resolved once, here: a name reused during the run belongs to
    # another process, whose flags are a host's own (measured: cleared by name at clear
    # time, a new holder lost the host's :send trace on both exit paths).
    pids = Enum.map(processes, &Process.whereis/1)
    Process.put(@claim, {flag, modules, pids})

    # The companion is up before anything is set, so whatever this function sets is cleared
    # whatever happens next: it clears on the tracer's exit, kill included, and at the
    # deadline. It runs at high priority for the same reason the tracer does, and the
    # tracer watches it back: a companion that died is a way out by name.
    companion = spawn_companion(self(), modules, pids, max_duration_ms, flag)
    _ = Process.monitor(companion)
    :persistent_term.put(@running, {flag, modules, companion})

    # The per-process flags first: a process already traced by someone else raises here,
    # and then nothing has been set yet. Should anything below raise after a pattern is
    # set, this process exits and the companion clears the patterns on its DOWN (measured:
    # a rescue that cleared them here was a mutant nothing could tell apart).
    for pid <- pids, do: :erlang.trace(pid, true, [:send, {:tracer, self()}])

    for m <- modules,
        do: :erlang.trace_pattern({m, :_, :_}, [{:_, [], [{:message, {:caller}}]}], [:local])

    # Calls are traced from every process, with the arity flag so no argument ever arrives.
    if modules != [], do: :erlang.trace(:all, true, [:call, :arity, {:tracer, self()}])

    # The collector's death is a way out by name, not a badarg on the next traced call into
    # a table that is gone.
    _ = Process.monitor(:ets.info(collector, :owner))

    {:ok,
     %{
       collector: collector,
       server: Keyword.fetch!(opts, :server),
       modules: modules,
       pids: pids,
       max_messages: Keyword.fetch!(opts, :max_messages),
       max_duration_ms: max_duration_ms,
       seen: 0,
       companion: companion,
       flag: flag
     }}
  end

  defp await_previous_companion do
    case :persistent_term.get(@running, nil) do
      {_flag, _modules, previous} when is_pid(previous) ->
        ref = Process.monitor(previous)

        receive do
          {:DOWN, ^ref, :process, ^previous, _} -> :ok
        after
          @await_companion -> Process.demonitor(ref, [:flush])
        end

      _ ->
        :ok
    end
  end

  @impl true
  def handle_info({:trace, _pid, :call, {m, _f, _arity}, {cm, _cf, _ca}}, state) do
    written(state, fn ->
      Observed.observe(
        state.collector,
        {:module, state.server, cm},
        {:module, state.server, m},
        :invoke
      )
    end)
  end

  def handle_info({:trace, _pid, :call, _mfa, :undefined}, state), do: counted(state)

  def handle_info({:trace, from, :send, _message, to}, state) do
    # A send to the tracer itself (stop/0 is one) is the tracer's own business, not an edge.
    written(state, fn ->
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
    end)
  end

  # A send to a process that is gone arrives under its own tag; it is counted like any
  # other trace message and never written -- there is no name to write it under.
  def handle_info({:trace, _from, :send_to_non_existing_process, _message, _to}, state),
    do: counted(state)

  def handle_info(:max_duration, state) do
    {:stop, {:shutdown, {:limit, :max_duration_ms, state.max_duration_ms}}, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, %{companion: pid} = state) do
    {:stop, {:shutdown, :companion_gone}, state}
  end

  def handle_info({:DOWN, _ref, :process, _owner, _reason}, state) do
    {:stop, {:shutdown, :collector_gone}, state}
  end

  # Anything else is not a trace message.
  def handle_info(_other, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    clear(state.modules, state.pids, self())
    send(state.companion, :cancel)
    :persistent_term.erase(@running)
    :ok
  end

  # A write into a table that is gone -- the collector died with messages still queued
  # ahead of its DOWN -- is the same way out as the DOWN itself.
  defp written(state, write) do
    write.()
    counted(state)
  rescue
    ArgumentError -> {:stop, {:shutdown, :collector_gone}, state}
  end

  # On every handled message: the flag first -- a deadline or a stop/0 that could not reach
  # the front of the queue ends the drain here -- then handled plus queued against the
  # limit: the moment the sum reaches it, the patterns go, so generation stops here rather
  # than after the limit-th write.
  defp counted(%{seen: seen, max_messages: max, flag: flag} = state) do
    seen = seen + 1
    state = %{state | seen: seen}

    # The queue length is read every 32nd message: under arrival the read costs ~2 µs
    # against ~0.1 µs for the handling itself (measured), and the window it widens is 32
    # messages. The read is best effort: a non-message signal ahead of the queue -- a
    # persistent-term erase sends every process one -- hides what is queued behind it
    # from the count (measured: a first read of 2..5 with 100 queued, in about one run in
    # fifteen). The hard bound does not depend on it: handled never exceeds the limit.
    queued =
      if rem(seen, 32) == 0 or seen == 1,
        do: elem(Process.info(self(), :message_queue_len), 1),
        else: 0

    case :atomics.get(flag, 1) do
      @deadline ->
        {:stop, {:shutdown, {:limit, :max_duration_ms, state.max_duration_ms}}, state}

      @stop ->
        {:stop, :normal, state}

      _ when seen + queued >= max ->
        clear(state.modules, state.pids, self())
        {:stop, {:shutdown, {:limit, :max_messages, max}}, state}

      _ ->
        {:noreply, state}
    end
  end

  # What the tracer set, unset: the pattern on every named module, and the send flag on
  # every named process. The call flags set on every process are not touched here: with
  # no pattern nothing is generated, and the BEAM removes a tracer's flags when it exits.
  # Clearing every process's flags -- `trace(:all, false, [:all])` -- wiped a host's own
  # trace flags on unrelated processes (measured), and cannot be scoped to one tracer.
  # A flag is cleared only where this tracer's is the flag on it: a named process that has
  # died answers `:undefined` and is skipped, and one a host re-traced under its own tracer
  # keeps that (measured).
  defp clear(modules, pids, tracer) do
    clear_patterns(modules)

    for pid <- pids,
        :erlang.trace_info(pid, :tracer) == {:tracer, tracer},
        do: :erlang.trace(pid, false, [:send])

    :ok
  end

  defp clear_patterns(modules) do
    for m <- modules, do: :erlang.trace_pattern({m, :_, :_}, false, [:local])
    :ok
  end

  # High priority, monitoring the tracer. At the deadline it clears and tells the tracer to
  # leave by name; on the tracer's exit for any reason it clears -- and erases the running
  # term only if the term is still its own tracer's.
  defp spawn_companion(tracer, modules, pids, max_duration_ms, flag) do
    spawn(fn ->
      Process.flag(:priority, :high)
      ref = Process.monitor(tracer)

      receive do
        :cancel ->
          :ok

        {:DOWN, ^ref, :process, ^tracer, _reason} ->
          after_death(flag, modules)
      after
        max_duration_ms ->
          clear(modules, pids, tracer)
          :atomics.put(flag, 1, @deadline)
          send(tracer, :max_duration)

          receive do
            {:DOWN, ^ref, :process, ^tracer, _reason} -> after_death(flag, modules)
            :cancel -> :ok
          end
      end
    end)
  end

  # Only its own: a companion that outlived the wait -- suspended from outside -- runs
  # after a new tracer claimed some of the same modules, and must not take those away
  # (measured). What the new tracer names is the new tracer's to clear, and the claim is
  # read from the running tracer itself, never from the public term (measured: a forged
  # term naming the dead tracer's own modules had passed for a claim and left them set).
  # The term is erased only when it is this companion's own.
  defp after_death(flag, modules) do
    claimed =
      case Process.whereis(@name) do
        nil ->
          []

        pid ->
          case claim(pid) do
            {_flag, modules, _pids} -> modules
            nil -> []
          end
      end

    clear_patterns(modules -- claimed)

    case running_term() do
      {^flag, _, _} -> :persistent_term.erase(@running)
      _ -> :ok
    end
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

  # A loaded (or loadable) module. That refuses the wildcard too -- `:_` is no module and
  # cannot be loaded -- and the wildcard is the one that matters: `{:_, :_, :_}` would trace
  # every module in the node and, on stop, clear every local pattern in it, the host's
  # included. (A separate `!= :_` test was a mutant nothing could tell apart.)
  defp modules(opts) do
    case Keyword.fetch!(opts, :modules) do
      list when is_list(list) ->
        if Enum.all?(list, &(is_atom(&1) and Code.ensure_loaded?(&1))),
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
