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
    in between is dropped too (measured: a receiver that exits after its last message
    loses that edge under some schedulings).

  What it refuses: a second tracer while one runs (`{:error, :already_running}`); starting
  without a running collector (`{:error, :collector_not_started}`); a limit that is not a
  positive integer -- there is no unbounded mode. It stops itself when `max_messages` trace
  messages have arrived or `max_duration_ms` has elapsed, clearing every pattern it set and
  every flag it set, and exits `{:shutdown, {:limit, which, value}}` so a host that monitors
  it knows why. `stop/0` is the third way out and clears the same way. The fourth is the
  collector dying under it: it monitors the collector and exits
  `{:shutdown, :collector_gone}`, clearing the same way, rather than failing on the next
  traced call into a table that is no longer there.

  It never calls `:dbg`. The tracer process is the trace receiver itself, so a slow host
  cannot make it drop into someone else's mailbox.
  """
  use GenServer

  alias BeamMCP.Connectome.Observed

  @name __MODULE__
  @defaults [max_messages: 1_000, max_duration_ms: 5_000, modules: [], processes: []]

  @doc """
  Starts the one tracer. Options: `collector:` (the running collector's name, required),
  `server:` (the server identity string the edges are filed under, required), `modules:`
  (modules whose calls are traced), `processes:` (registered names whose sends are traced),
  `max_messages:` (default 1_000), `max_duration_ms:` (default 5_000).
  """
  @spec start(keyword()) ::
          {:ok, pid()}
          | {:error, :already_running | :collector_not_started | {:invalid, atom(), term()}}
  def start(opts) do
    opts = Keyword.merge(@defaults, opts)

    with :ok <- positive(opts, :max_messages),
         :ok <- positive(opts, :max_duration_ms),
         :ok <- atoms(opts, :modules),
         :ok <- atoms(opts, :processes),
         :ok <- server(opts),
         :ok <- collector_running(opts) do
      case GenServer.start(__MODULE__, opts, name: @name) do
        {:ok, pid} -> {:ok, pid}
        {:error, {:already_started, _}} -> {:error, :already_running}
      end
    end
  end

  @doc "Stops the tracer if one runs, clearing everything it set. `:ok` either way."
  @spec stop() :: :ok
  def stop do
    case Process.whereis(@name) do
      nil -> :ok
      pid -> GenServer.stop(pid, :normal)
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
    modules = Keyword.fetch!(opts, :modules)
    processes = Keyword.fetch!(opts, :processes)

    for m <- modules,
        do: :erlang.trace_pattern({m, :_, :_}, [{:_, [], [{:message, {:caller}}]}], [:local])

    # Calls are traced from every process, with the arity flag so no argument ever arrives.
    if modules != [], do: :erlang.trace(:all, true, [:call, :arity, {:tracer, self()}])

    for p <- processes,
        pid = Process.whereis(p),
        pid != nil,
        do: :erlang.trace(pid, true, [:send, {:tracer, self()}])

    timer = Process.send_after(self(), :max_duration, Keyword.fetch!(opts, :max_duration_ms))

    # The collector's death is a way out by name, not a badarg on the next traced call into
    # a table that is gone (found by a lane that killed the collector under a running tracer).
    collector = Keyword.fetch!(opts, :collector)
    _ = Process.monitor(:ets.info(collector, :owner))

    {:ok,
     %{
       collector: Keyword.fetch!(opts, :collector),
       server: Keyword.fetch!(opts, :server),
       modules: modules,
       processes: processes,
       max_messages: Keyword.fetch!(opts, :max_messages),
       max_duration_ms: Keyword.fetch!(opts, :max_duration_ms),
       seen: 0,
       timer: timer
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

  def handle_info(:max_duration, state) do
    {:stop, {:shutdown, {:limit, :max_duration_ms, state.max_duration_ms}}, state}
  end

  def handle_info({:DOWN, _ref, :process, _owner, _reason}, state) do
    {:stop, {:shutdown, :collector_gone}, state}
  end

  def handle_info(_other, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    clear(state)
    :ok
  end

  defp counted(%{seen: seen, max_messages: max} = state) when seen + 1 >= max do
    {:stop, {:shutdown, {:limit, :max_messages, max}}, %{state | seen: seen + 1}}
  end

  defp counted(state), do: {:noreply, %{state | seen: state.seen + 1}}

  # Everything set in init/1, unset: the pattern on every module. The flags need no
  # unsetting -- the BEAM removes every trace flag a tracer set the moment the tracer
  # process exits (measured: a mutant that dropped the explicit unset survived, because the
  # flags were gone anyway). The test that reads the flags after a stop pins that.
  defp clear(state) do
    Process.cancel_timer(state.timer)
    for m <- state.modules, do: :erlang.trace_pattern({m, :_, :_}, false, [:local])
    :ok
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

  defp atoms(opts, key) do
    case Keyword.fetch!(opts, key) do
      list when is_list(list) ->
        if Enum.all?(list, &is_atom/1), do: :ok, else: {:error, {:invalid, key, list}}

      other ->
        {:error, {:invalid, key, other}}
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
