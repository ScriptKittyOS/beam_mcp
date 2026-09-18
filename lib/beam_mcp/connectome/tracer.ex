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
    to the callee's -- a call pattern with a `{caller}` action and the `:arity` flag, so a
    trace message carries `{m, f, arity}` and never an argument. The caller is the frame
    the BEAM keeps: a call in tail position has no frame of its own, so it is attributed to
    the caller's caller (measured on a fixture: a module's tail call into a second module
    is filed under whoever called the first). A call whose caller the BEAM cannot name at
    all is counted against the message limit and not written;
  - a send from a traced process to a *registered* process, as a `:message` edge by
    registered name -- the message term is never read, and a send to an unregistered
    process is dropped rather than written under a pid. Names are resolved when the trace
    message is handled, not when the send happened: a process that exited or unregistered
    in between is dropped too. OTP's own registered processes -- the code server, a logger
    handler, telemetry's table owner -- are names like any other, so a traced process's
    sends to them are edges too; a host that wants only its own graph filters them. The
    one registered process a send to which is no edge is the tracer itself: `stop/0` and a
    `:sys` call are the tracer's own business, not the graph's.

  **One trace session, the tracer's own.** Everything the tracer sets, it sets inside one
  OTP trace session (`:trace.session_create/3`, OTP 27) whose tracer is the tracer process:
  its call patterns on the named modules, the call flag on every process in the node --
  the ones alive now and the ones spawned while it runs -- and the send flag on the named
  processes. Sessions are isolated from each other and from the legacy `:erlang.trace/3`
  session a host may be using, so a process a host already traces is traced by this
  session as well and its calls are edges (measured: both tracers received the call); a
  host's own pattern on a module the tracer names is neither fed by the tracer's pattern
  nor touched by its clear (measured: the host's call tracer saw only its own pattern's
  messages, and its pattern read `local` after the tracer's session was gone); and nothing
  here reads or clears a flag or a pattern that is not the session's. The BEAM discards a
  trace event whose tracer is the process that generated it, so the tracer never traces its
  own writes (measured).

  What it refuses: a second tracer while one runs (`{:error, :already_running}`); starting
  without a running collector (`{:error, :collector_not_started}`); a limit that is not a
  positive integer -- there is no unbounded mode -- or a duration beyond the BEAM's timer
  range (4 294 967 295 ms, the largest a `receive ... after` takes); the wildcard `:_` or a module that cannot
  be loaded in `modules:`; a name in `processes:` that is not registered
  (`{:error, {:not_registered, name}}`); and a start that failed part-way, which leaves
  nothing set and answers `{:error, {:init_failed, reason}}` -- a name in `processes:`
  that is registered to a port rather than a process, or whose holder exited between the
  check and the start, is the cause that remains.

  **The limits, and what they bound.** `max_messages` counts trace messages as the tracer
  *handles* them; the BEAM queues them as they arrive, and under load the tracer is
  scheduled less often than the processes it traces. Two things keep that queue small: the
  tracer runs at high priority, and on the first and every 32nd handled message it compares
  handled + queued against the limit and, the moment the sum reaches it, destroys its
  session and exits on that message -- generation stops there, and what was queued behind
  it is discarded. So the memory bound is the node-wide call rate
  into the named modules times the tracer's scheduling latency at high priority, not
  `max_messages` (measured: 64 hot callers against a limit of 1 000 peaked at 12.8 million
  queued messages before these two measures, and from some tens of thousands to a
  hundred-odd thousand after, run to run; with a limit too large to reach, 32 hot callers
  queued some millions in a 100 ms window -- the window times the rate is the bound, and
  the limit is what keeps the window short). The mailbox is kept off-heap, so a large
  queue is not copied at every collection while it drains (measured: on-heap, a drain
  under continuous arrival fell to 191 µs per message). A `:send` trace message carries
  the sent term, so a traced process's sends are copied into the tracer's mailbox at
  their own size until they are handled and dropped unread (measured: one traced send of
  a million-element list put 16 MB on the tracer); that bound is the traced processes'
  own message sizes, and nothing of a term is written. `max_duration_ms` is enforced by a
  companion process that raises a flag and destroys the session at the deadline from
  outside the tracer's mailbox, so tracing stops on time even when the tracer is starved
  -- the flag is raised first and the session destroyed second, so the writes stop before
  the generation does -- and the tracer reads the flag before every write, so it exits
  `{:shutdown, {:limit, :max_duration_ms, ms}}` on the next message it handles, without a
  row, rather than after draining what was queued: nothing lands after the flag is raised.
  `stop/0` raises the same flag and then destroys the session, for the same reason, then
  stops the tracer with a finite wait of five seconds (measured, eight hot callers: rows
  landing during the call fell from 4 900-7 500 to 62-939 with the order swapped; what
  remains is the caller's own scheduling before its first instruction). `stop/0` reads
  the tracer's own claim -- the flag and the session handle, in its process dictionary,
  which nothing outside the tracer can write -- and the companion holds the same claim in
  its closure from the start. A claim of another shape, put there by a process that took
  the name, is no claim (measured: it had made `stop/0` raise).

  **Nothing left behind, on every path.** A session's settings are removed in one call,
  `:trace.session_destroy/1` -- `stop/0`, the message limit and the deadline each make
  that call, and so does `terminate/2` -- and a session is destroyed by the BEAM itself
  when the last copy of its handle is garbage collected (measured: the handle's only
  holder killed, the pattern was gone within 20 ms). The handle is held by the tracer and
  by its companion and by nothing else this module writes -- never in a persistent term,
  which would keep a dead tracer's session, and its breakpoints, alive until erased
  (measured); a copy anywhere is a holder too, and `:sys.get_state/1` on the tracer makes
  one on the caller's heap that holds the session up until that process next collects
  (measured: 50 ms after both holders had died, the session was still listed). The
  companion monitors the tracer and exits on its exit -- a kill included, which skips
  `terminate/2` -- and that exit is the clear: the last holder gone, the session goes
  with it. So the window the legacy tracer had, the companion killed and then the tracer
  killed before it handles that death, closes by physics too, whatever modules the
  session named. A session whose tracer has died but whose handle is still held keeps
  its patterns set -- the BEAM drops a dead tracer's process flags, not its patterns --
  at a cost per call into those modules (measured: 200 000 calls, from the baseline's
  order to 2.4 times it, run to run): a companion suspended from outside is such a
  holder, and `terminate/2`'s own destroy is what ends the session on an orderly exit
  while it is. A start that fails part-way destroys its session before the reason leaves
  `init/1`, because the error term carries the raise's arguments, the handle among them,
  and a copy of a handle anywhere is a holder (measured: a host keeping that error kept an
  empty session listed for as long as it did).
  The tracer watches the companion back and leaves `{:shutdown, :companion_gone}` if it
  dies, since it is the only enforcer of the deadline; a hot reload of this module purges
  the companion, an anonymous function of the old code, and ends a running trace that way
  (measured), and `:code.soft_purge/1` refuses while a trace runs, for the same reason.

  Exits: `{:shutdown, {:limit, :max_messages, n}}`, `{:shutdown, {:limit, :max_duration_ms,
  ms}}`, `:normal` from `stop/0`, `{:shutdown, :collector_gone}` when the collector dies
  under it -- met as its DOWN or as the first write into the table that is gone, whichever
  comes first in the queue -- and `{:shutdown, :companion_gone}`. The tracer is started
  unlinked and traps exits, so no process's exit signal short of an untrappable `:kill`
  ends it -- `Process.exit(pid, :shutdown)` from the process that started it or from any
  other, a linked process dying -- each is a message it ignores, not a stop (measured):
  tracing goes on to its limits, and `stop/0` is the way to end it from outside. It never
  calls `:dbg`.

  **The threat model, which is the boundary of every claim above.** In scope: accident and
  failure on a node running only code the host put there -- crashes, kills, restarts and the
  host's supervisor, a registered name reused by an unrelated process, a host tracing its
  own processes under the legacy tracer or under a session of its own, hot reload,
  starvation under load, and the public API called wrongly or in the wrong order. Out of
  scope: an adversary executing code inside the same node -- a process that registers
  itself under this module's name, a crafted process dictionary, a handle taken from the
  tracer's dictionary and destroyed. Such an adversary can already read the collector's table directly, call the host's
  dispatch function, replace a module with `:code.load_binary/3`, or trace every process
  itself; this tracer is not a security boundary against it, and nothing in this package
  makes it one. The shape guard on the claim is robustness -- it keeps `stop/0` total
  against a claim of the wrong shape -- not a defence.
  """
  use GenServer

  alias BeamMCP.Connectome.Observed

  @name __MODULE__
  # The session's name, as `:trace.session_info/1` reports it beside a host's own sessions.
  @session :beam_mcp_tracer
  @defaults [max_messages: 1_000, max_duration_ms: 5_000, modules: [], processes: []]
  @stop_timeout 5_000
  # The largest timeout a `receive ... after` takes: the companion's deadline is one, and a
  # larger value raised :timeout_value in the companion on its first instruction -- a start
  # that answered {:ok, pid} and left {:shutdown, :companion_gone} at once (measured).
  @max_duration_ms 4_294_967_295
  # The tracer's own claim -- the flag and the session handle -- in its process dictionary,
  # which nothing outside the tracer can write. `stop/0` reads it there; the companion
  # holds the same two in its closure.
  @claim {__MODULE__, :claim}
  # A one-word flag the tracer reads on every handled message, set from outside its
  # mailbox: 1 = the deadline passed, 2 = stop/0 was called. A message would queue behind
  # what is already there; the flag is read before the next write.
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
         :ok <- in_timer_range(opts, :max_duration_ms),
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
  Stops the tracer if one runs: the flag is raised and the session destroyed first, so
  tracing stops now rather than after the queue, then the process is stopped with a finite
  wait. `:ok` either way.
  """
  @spec stop() :: :ok
  def stop do
    case Process.whereis(@name) do
      nil ->
        :ok

      pid ->
        # The tracer's own claim: a stop that asked the tracer would queue behind everything
        # it has not handled (measured: nine million rows written after the call). The keyed
        # dictionary read is not queue-ordered (measured: 2 µs).
        # The flag first, the session second: the flag stops the writes on the next message
        # the tracer handles, the destroy stops the generation; in the other order, rows
        # landed for as long as the clear took (measured: 4 900-7 500 under eight hot
        # callers).
        case claim(pid) do
          {flag, session} -> raise_and_destroy(flag, session)
          nil -> :ok
        end

        GenServer.stop(pid, :normal, @stop_timeout)
    end
  catch
    :exit, _ -> :ok
  end

  # A crafted claim -- a flag that is no atomics reference, a session that is no handle --
  # raises out of `:atomics.put/3` or `session_destroy/1` (measured, both): nothing to raise
  # or destroy, and the stop itself still goes ahead.
  defp raise_and_destroy(flag, session) do
    :atomics.put(flag, 1, @stop)
    destroy(session)
  rescue
    ArgumentError -> false
  end

  # No claim, whether the process is gone (`Process.info/2` answers nil for a dead pid --
  # the tracer left between the whereis and this read), has none, or holds one that is not
  # a pair: the same answer. The name can be taken by any process, and one that squats it
  # with a crafted claim already refuses every start; it must not turn `stop/0` into a
  # raise (measured, by a lane) -- a pair of the wrong contents is `raise_and_destroy/2`'s
  # to rescue, since the BEAM, not this module, knows what an atomics reference or a
  # session handle looks like (an `is_reference/1` check here was a mutant nothing could
  # tell apart once that rescue existed). One key, not the whole dictionary: the keyed read
  # costs 2 µs where the copy cost up to a millisecond on a loaded tracer (measured).
  defp claim(pid) do
    case :erlang.process_info(pid, {:dictionary, @claim}) do
      {{:dictionary, @claim}, {_flag, _session} = claim} -> claim
      _ -> nil
    end
  end

  # Idempotent: `false` for a session already destroyed -- by an earlier call, by the
  # companion, or by the garbage collector. Every caller but `raise_and_destroy/2` hands it
  # a handle this module made; that one rescues the crafted case itself.
  defp destroy(session), do: :trace.session_destroy(session)

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

    # The session first, with this process as its tracer; the claim beside it, so a stop
    # can find both without asking. The named processes are resolved once, here: a name
    # reused during the run belongs to another process, and the session's flag is on the
    # pid it was set on, not on the name.
    session = :trace.session_create(@session, self(), [])
    flag = :atomics.new(1, [])
    Process.put(@claim, {flag, session})

    # The companion enforces the deadline from outside this process's mailbox and is the
    # session's other holder. It runs at high priority for the same reason the tracer
    # does, and the tracer watches it back: a companion that died is a way out by name.
    # Should anything below raise, this process exits and the companion follows, and the
    # session goes with its holders -- its place in this order does not matter (a mutant
    # that spawned it after the settings was one nothing could tell apart).
    companion = spawn_companion(self(), session, max_duration_ms, flag)
    _ = Process.monitor(companion)

    # A raise below ends this process, and the error term start/1 answers carries the
    # raise's arguments -- the handle among them -- onto the caller's heap, where a copy is
    # a holder (measured by a lane: a host keeping the error kept an empty session listed
    # for as long as it did). So the session is destroyed HERE, before the reason leaves: a
    # handle to a destroyed session is inert wherever it is copied.
    try do
      for name <- processes,
          do: :trace.process(session, Process.whereis(name), true, [:send])

      for m <- modules,
          do:
            :trace.function(session, {m, :_, :_}, [{:_, [], [{:message, {:caller}}]}], [
              :local
            ])

      # Calls are traced from every process, with the arity flag so no argument ever arrives.
      if modules != [], do: :trace.process(session, :all, true, [:call, :arity])
    rescue
      e ->
        destroy(session)
        reraise e, __STACKTRACE__
    end

    # The collector's death is a way out by name, not a badarg on the next traced call into
    # a table that is gone.
    _ = Process.monitor(:ets.info(collector, :owner))

    {:ok,
     %{
       collector: collector,
       server: Keyword.fetch!(opts, :server),
       session: session,
       max_messages: Keyword.fetch!(opts, :max_messages),
       max_duration_ms: max_duration_ms,
       seen: 0,
       companion: companion,
       flag: flag
     }}
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
    destroy(state.session)
    send(state.companion, :cancel)
    :ok
  end

  # A write into a table that is gone -- the collector died with messages still queued
  # ahead of its DOWN -- is the same way out as the DOWN itself.
  # The flag before the write, so nothing lands after it is raised: the first message
  # handled after a stop or the deadline ends the tracer without a row.
  defp written(%{flag: flag} = state, write) do
    case :atomics.get(flag, 1) do
      @deadline ->
        {:stop, {:shutdown, {:limit, :max_duration_ms, state.max_duration_ms}}, state}

      @stop ->
        {:stop, :normal, state}

      _ ->
        write.()
        counted(state)
    end
  rescue
    ArgumentError -> {:stop, {:shutdown, :collector_gone}, state}
  end

  # On every handled message: the flag first -- a deadline or a stop/0 that could not reach
  # the front of the queue ends the drain here -- then handled plus queued against the
  # limit: the moment the sum reaches it, the session goes, so generation stops here rather
  # than after the limit-th write.
  defp counted(%{seen: seen, max_messages: max} = state) do
    seen = seen + 1
    state = %{state | seen: seen}

    # The queue length is read every 32nd message: under arrival the read costs ~2 µs
    # against ~0.1 µs for the handling itself (measured), and the window it widens is 32
    # messages. The read is best effort: a non-message signal ahead of the queue hides
    # what is queued behind it from the count (measured: a first read of 2..5 with 100
    # queued, in about one run in fifteen). The hard bound does not depend on it: handled
    # never exceeds the limit.
    queued =
      if rem(seen, 32) == 0 or seen == 1,
        do: elem(Process.info(self(), :message_queue_len), 1),
        else: 0

    if seen + queued >= max do
      destroy(state.session)
      {:stop, {:shutdown, {:limit, :max_messages, max}}, state}
    else
      {:noreply, state}
    end
  end

  # High priority, monitoring the tracer. At the deadline it raises the flag, destroys the
  # session and tells the tracer to leave by name. On the tracer's exit for any reason it
  # exits too, and that is the clear: it is the session's last holder, and a session whose
  # every handle is gone is destroyed by the BEAM (measured: within 20 ms of the holder's
  # death). An explicit destroy here was a mutant nothing could tell apart -- the exit is
  # the same event -- so there is none; the deadline's destroy is explicit because there
  # the companion lives on. It stays until the tracer is gone, so its own death is never
  # mistaken for the deadline. Its handle reaches its own session and nothing else's: a
  # later tracer's session is another handle.
  defp spawn_companion(tracer, session, max_duration_ms, flag) do
    spawn(fn ->
      Process.flag(:priority, :high)
      ref = Process.monitor(tracer)

      receive do
        :cancel ->
          :ok

        {:DOWN, ^ref, :process, ^tracer, _reason} ->
          :ok
      after
        max_duration_ms ->
          :atomics.put(flag, 1, @deadline)
          destroy(session)
          send(tracer, :max_duration)

          receive do
            {:DOWN, ^ref, :process, ^tracer, _reason} -> :ok
            :cancel -> :ok
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

  defp in_timer_range(opts, key) do
    case Keyword.fetch!(opts, key) do
      n when n <= @max_duration_ms -> :ok
      other -> {:error, {:invalid, key, other}}
    end
  end

  # A loaded (or loadable) module. That refuses the wildcard too -- `:_` is no module and
  # cannot be loaded -- and the wildcard is the one that matters: `{:_, :_, :_}` would trace
  # every module in the node. (A separate `!= :_` test was a mutant nothing could tell apart.)
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
