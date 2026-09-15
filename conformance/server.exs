# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# THE CONFORMANCE HARNESS'S SERVER: the package's own HTTP transport on Bandit, with a catalog
# that carries the diagnostic tools the official suite calls BY NAME -- and only those this
# package can honestly serve. `test_simple_text` returns text; `test_error_handling` returns a
# tool error (`isError: true`). Tools the suite names for content types this package does not
# emit (image, audio, embedded resources), for capabilities it does not read (`test_missing_
# capability`), for streams and logging (`test_streaming_elicitation`, `test_logging_tool`) and
# for the tasks extension are NOT here: a tool invented to make a scoreboard greener would be a
# claim the package cannot keep, and their scenarios are baselined with a reason word instead.
#
# Run by tools/conformance.sh, never shipped: `conformance/` is not in the package's files.
#
#     mix run conformance/server.exs            (PORT, default 4321)

defmodule BeamMCP.Conformance.Catalog do
  @behaviour BeamMCP.Catalog

  @impl true
  def capabilities do
    %{
      tools: [
        %BeamMCP.ToolSpec{
          name: :echo,
          command_class: :observe,
          mode: :read_only,
          description: "Echoes its message.",
          input_schema: %{
            "type" => "object",
            "properties" => %{"message" => %{"type" => "string"}}
          }
        },
        %BeamMCP.ToolSpec{
          name: :test_simple_text,
          command_class: :observe,
          mode: :read_only,
          description: "The suite's simple-text tool: returns text.",
          input_schema: %{"type" => "object", "properties" => %{}}
        },
        %BeamMCP.ToolSpec{
          name: :test_error_handling,
          command_class: :observe,
          mode: :read_only,
          description: "The suite's error tool: returns a tool error.",
          input_schema: %{"type" => "object", "properties" => %{}}
        }
      ],
      resources: [],
      prompts: []
    }
  end
end

dispatch = fn
  :test_error_handling, _args, _opts -> {:error, "This tool intentionally returns an error"}
  :test_simple_text, _args, _opts -> {:ok, "Hello from beam_mcp"}
  :echo, args, _opts -> {:ok, %{"echo" => Map.get(args, :message, "")}}
end

port = String.to_integer(System.get_env("PORT", "4321"))

{:ok, _} =
  Bandit.start_link(
    plug: {
      BeamMCP.Transport.HTTP,
      # The suite's dns-rebinding scenario expects localhost origins accepted and others
      # refused; the list is what a local harness legitimately allows.
      catalog: BeamMCP.Conformance.Catalog,
      dispatch: dispatch,
      authorize: fn _conn -> :ok end,
      allowed_origins: [
        "http://localhost",
        "http://127.0.0.1",
        "http://localhost:#{port}",
        "http://127.0.0.1:#{port}"
      ]
    },
    port: port,
    ip: {127, 0, 0, 1}
  )

IO.puts("conformance server up on http://127.0.0.1:#{port}/")
Process.sleep(:infinity)
