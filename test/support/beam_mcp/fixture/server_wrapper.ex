# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Fixture.ServerWrapper do
  @moduledoc false
  # Modules for the `:server` seam's tests. `Answers` is the shape a host puts above the core:
  # it answers one method itself (`tools/call`, the method an approval wrapper intercepts) and
  # hands every other message to `BeamMCP.Server`; its state is its own map, with the core's
  # state inside it, so a transport that reads anything of the state shows here. `TwoOnly`
  # exports `new/1` and `handle_message/2` and no `shutdown?/1` -- what a wrapper for the HTTP
  # transport alone needs. `NewOnly` and `HandleOnly` each lack exactly one of the two every
  # transport reaches, so each per-function check is pinned on its own (a lane measured that
  # dropping any one name from a transport's list survived the suite with only `WrongArity`,
  # which fails every check at once). `WrongArity` and `NotAServer` are refused at init.
  defmodule Answers do
    @moduledoc false
    @behaviour BeamMCP.Server
    alias BeamMCP.Server

    @impl true
    def new(opts) do
      send(self(), {:wrapper_new, opts})
      %{core: Server.new(opts), answered: 0}
    end

    @impl true
    def handle_message(%{core: _} = state, %{"method" => "tools/call", "id" => id}) do
      {%{state | answered: state.answered + 1},
       %{
         "jsonrpc" => "2.0",
         "id" => id,
         "result" => %{
           "content" => [%{"type" => "text", "text" => "answered by the wrapper"}],
           "isError" => false
         }
       }}
    end

    def handle_message(%{core: core} = state, message) do
      {core, response} = Server.handle_message(core, message)
      {%{state | core: core}, response}
    end

    @impl true
    def shutdown?(%{core: core}), do: Server.shutdown?(core)
  end

  defmodule TwoOnly do
    @moduledoc false
    @behaviour BeamMCP.Server
    @impl true
    def new(opts), do: BeamMCP.Server.new(opts)
    @impl true
    def handle_message(state, message), do: BeamMCP.Server.handle_message(state, message)
  end

  defmodule NewOnly do
    @moduledoc false
    def new(opts), do: BeamMCP.Server.new(opts)
    def shutdown?(state), do: BeamMCP.Server.shutdown?(state)
  end

  defmodule HandleOnly do
    @moduledoc false
    def handle_message(state, message), do: BeamMCP.Server.handle_message(state, message)
    def shutdown?(state), do: BeamMCP.Server.shutdown?(state)
  end

  defmodule WrongArity do
    @moduledoc false
    def new(_opts, _extra), do: %{}
    def handle_message(state, _message, _extra), do: {state, nil}
    def shutdown?(_state), do: false
  end

  defmodule NotAServer do
    @moduledoc false
    def something_else, do: :ok
  end
end
