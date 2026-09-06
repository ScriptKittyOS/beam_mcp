# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Server do
  alias BeamMCP.Schema

  @moduledoc false

  alias BeamMCP.ToolSpec

  # Two revisions, two eras. 2026-07-28 removed the initialize handshake and protocol-level
  # sessions; 2025-11-25 and earlier open with initialize. The spec calls a server serving
  # both "dual-era" and fixes the discriminator: modern per-request _meta, or initialize.
  @modern_version "2026-07-28"
  @legacy_version "2025-11-25"
  @supported_versions [@modern_version, @legacy_version]

  @version_meta_key "io.modelcontextprotocol/protocolVersion"
  @server_info_meta_key "io.modelcontextprotocol/serverInfo"
  @default_server_name "beam_mcp"
  # Read from the application spec rather than restated here. A hardcoded copy beside the one
  # in mix.exs is a transcription defect waiting for the first release that updates one of them.
  @server_version Mix.Project.config()[:version]

  @typedoc """
  The dispatch contract. A host supplies a function of this shape; the server calls it and
  never inspects what it does. Ultraviolet's `Dispatch.safe_call/3` satisfies it.
  """
  @type dispatch :: (atom(), map(), keyword() -> {:ok, term()} | {:error, term()})

  @type state :: %{
          dispatch: (atom(), map(), keyword() -> {:ok, term()} | {:error, term()}),
          dispatch_opts: keyword(),
          initialized?: boolean(),
          server_name: String.t(),
          shutdown?: boolean(),
          tool_catalog: module()
        }

  @spec new(keyword()) :: state()
  def new(opts \\ []) do
    %{
      dispatch: Keyword.get(opts, :dispatch),
      dispatch_opts: Keyword.get(opts, :dispatch_opts, []),
      initialized?: false,
      server_name: Keyword.get(opts, :server_name, @default_server_name),
      shutdown?: false,
      tool_catalog: Keyword.fetch!(opts, :tool_catalog)
    }
  end

  @spec shutdown?(state()) :: boolean()
  def shutdown?(state), do: state.shutdown?

  @spec handle_message(state(), map() | list()) :: {state(), map() | nil}
  # JSON-RPC batching was added in 2025-03-26 and removed in 2025-06-18. Neither supported
  # revision includes it, so a batch is refused rather than half-processed.
  def handle_message(state, messages) when is_list(messages) do
    {state,
     error(nil, -32_600, "Batch requests are not supported at any supported protocol version")}
  end

  # server/discover is mandatory in 2026-07-28, and on stdio it doubles as the era probe: a
  # client sends it before it knows what it is talking to. So it is answered whether or not
  # the request carries modern _meta.
  def handle_message(state, %{"jsonrpc" => "2.0", "id" => id, "method" => "server/discover"}) do
    {state,
     result(id, %{
       "protocolVersions" => @supported_versions,
       "capabilities" => %{"tools" => %{"listChanged" => false}},
       "serverInfo" => %{"name" => state.server_name, "version" => @server_version}
     })}
  end

  # An initialize request selects legacy semantics, whatever else it carries.
  def handle_message(state, %{"jsonrpc" => "2.0", "id" => id, "method" => "initialize"} = message) do
    requested = get_in(message, ["params", "protocolVersion"]) || @legacy_version

    if requested in @supported_versions do
      response =
        result(id, %{
          "protocolVersion" => requested,
          "capabilities" => %{"tools" => %{"listChanged" => false}},
          "serverInfo" => %{"name" => state.server_name, "version" => @server_version}
        })

      {%{state | initialized?: true}, response}
    else
      {state, unsupported_version(id, requested)}
    end
  end

  # A request carrying modern per-request _meta is served statelessly under 2026-07-28.
  def handle_message(
        state,
        %{"jsonrpc" => "2.0", "id" => id, "_meta" => %{@version_meta_key => version}} = message
      ) do
    cond do
      version not in @supported_versions ->
        {state, unsupported_version(id, version)}

      # ping was removed in 2026-07-28. The legacy handler must not inherit it.
      message["method"] == "ping" ->
        {state, error(id, -32_601, "Method not found: ping")}

      true ->
        {next, response} = handle_message(state, Map.drop(message, ["_meta"]))
        {next, modernise(response, state)}
    end
  end

  def handle_message(state, %{"jsonrpc" => "2.0", "method" => "notifications/initialized"}) do
    {%{state | initialized?: true}, nil}
  end

  def handle_message(state, %{"jsonrpc" => "2.0", "id" => id, "method" => "ping"}) do
    {state, result(id, %{})}
  end

  def handle_message(state, %{"jsonrpc" => "2.0", "id" => id, "method" => "tools/list"}) do
    tools = Enum.map(state.tool_catalog.all(), &tool_definition/1)
    {state, result(id, %{"tools" => tools})}
  end

  def handle_message(
        state,
        %{
          "jsonrpc" => "2.0",
          "id" => id,
          "method" => "tools/call",
          "params" => %{"name" => name} = params
        }
      ) do
    arguments = Map.get(params, "arguments", %{})

    case find_tool(state, name) do
      {:ok, %ToolSpec{} = spec} ->
        response =
          case validate_and_dispatch(state, spec, arguments) do
            {:ok, payload} ->
              result(id, tool_success(payload))

            {:error, reason} ->
              result(id, tool_failure(reason))
          end

        {state, response}

      :error ->
        {state, error(id, -32_601, "Unknown tool: #{name}")}
    end
  end

  def handle_message(state, %{"jsonrpc" => "2.0", "id" => id, "method" => "shutdown"}) do
    {%{state | shutdown?: true}, result(id, %{})}
  end

  def handle_message(state, %{"jsonrpc" => "2.0", "method" => "exit"}) do
    {%{state | shutdown?: true}, nil}
  end

  def handle_message(state, %{"jsonrpc" => "2.0", "id" => id, "method" => method}) do
    {state, error(id, -32_601, "Method not found: #{method}")}
  end

  def handle_message(state, %{"id" => id}) do
    {state, error(id, -32_600, "Invalid Request")}
  end

  def handle_message(state, _message) do
    {state, nil}
  end

  defp tool_definition(%ToolSpec{} = tool) do
    %{
      "name" => Atom.to_string(tool.name),
      "description" => tool.description,
      "inputSchema" => tool.input_schema,
      "annotations" => %{
        "destructiveHint" => tool.mode == :proposal,
        "idempotentHint" => tool.mode == :read_only,
        "openWorldHint" => false,
        "readOnlyHint" => tool.mode == :read_only
      }
    }
  end

  defp tool_success(payload) do
    encoded = to_json_value(payload)

    %{
      "content" => [%{"type" => "text", "text" => Jason.encode!(encoded, pretty: true)}],
      "structuredContent" => encoded,
      "isError" => false
    }
  end

  # An error crossing the wire carries JSON. `structuredContent` gets the term as data so a
  # client can read a field; `content` gets a sentence a person can read. Neither carries
  # Elixir syntax: a caller has no reason to know what language this is written in, and no way
  # to parse its terms.
  defp tool_failure(reason) do
    %{
      "content" => [%{"type" => "text", "text" => error_text(reason)}],
      "structuredContent" => %{"error" => to_json_value(reason)},
      "isError" => true
    }
  end

  defp error_text(reason) when is_binary(reason), do: reason

  defp error_text(%{"tool" => tool, "reason" => detail}), do: "#{tool}: #{detail}"

  defp error_text(reason) when is_map(reason) do
    reason
    |> to_json_value()
    |> Enum.map_join(", ", fn {key, value} -> "#{key}: #{stringify(value)}" end)
  end

  defp error_text(reason), do: stringify(to_json_value(reason))

  defp stringify(value) when is_binary(value), do: value
  defp stringify(value) when is_number(value), do: to_string(value)
  defp stringify(value), do: Jason.encode!(value)

  # One lookup governs both paths: a tool is callable exactly when the injected catalog names
  # it, and the spec it returns carries the schema that will be enforced.
  defp find_tool(state, name) when is_binary(name) do
    Enum.find_value(state.tool_catalog.all(), :error, fn spec ->
      if Atom.to_string(spec.name) == name, do: {:ok, spec}
    end)
  end

  defp find_tool(state, name) when is_atom(name),
    do: find_tool(state, Atom.to_string(name))

  defp find_tool(_state, _name), do: :error

  # The advertised schema is the contract. Validate the wire form -- string keys, as the
  # client sent them -- before normalising, so `required` and `additionalProperties`
  # mean what tools/list says they mean.
  defp validate_and_dispatch(state, %ToolSpec{} = spec, arguments) do
    case Schema.validate(arguments, spec.input_schema) do
      :ok ->
        args = normalize_arguments(arguments, spec.input_schema)
        state.dispatch.(spec.name, args, state.dispatch_opts)

      {:error, reason} ->
        {:error,
         %{"tool" => Atom.to_string(spec.name), "reason" => "invalid arguments: #{reason}"}}
    end
  end

  # Only reached with a map: Schema.validate/2 rejects anything else first.
  #
  # The permitted key set is **derived from the schema the catalog supplied**, not from a list
  # compiled in here. A declared key is handed to dispatch as an atom; an undeclared one is
  # dropped, because whether it was allowed at all was already decided by validation against
  # `additionalProperties`.
  #
  # Values are passed through unchanged apart from JSON normalisation. Coercing a value to a
  # domain term is the host's business: this module has no way to know that one tool's string
  # is another system's enum, and guessing is how a generic layer acquires someone else's
  # domain.
  defp normalize_arguments(arguments, schema) when is_map(arguments) do
    atoms = declared_atoms(schema)

    for {key, value} <- arguments,
        {:ok, atom} <- [Map.fetch(atoms, key)],
        into: %{},
        do: {atom, to_json_value(value)}
  end

  defp declared_atoms(schema) do
    schema
    |> Map.get("properties", %{})
    |> Map.keys()
    |> Map.new(fn key -> {key, String.to_atom(key)} end)
  end

  defp to_json_value(value) when is_map(value) do
    Map.new(value, fn {key, nested_value} ->
      normalized_key = if is_atom(key), do: Atom.to_string(key), else: key
      {normalized_key, to_json_value(nested_value)}
    end)
  end

  defp to_json_value(value) when is_list(value), do: Enum.map(value, &to_json_value/1)
  defp to_json_value(value) when is_atom(value), do: Atom.to_string(value)
  defp to_json_value(value), do: value

  defp unsupported_version(id, requested) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "error" => %{
        "code" => -32_022,
        "message" => "Unsupported protocol version",
        "data" => %{"supported" => @supported_versions, "requested" => requested}
      }
    }
  end

  # 2026-07-28 requires resultType on every result, and servers SHOULD identify themselves in
  # each result's _meta. Applied only on the modern path: a legacy result carries neither.
  defp modernise(%{"result" => payload} = response, state) when is_map(payload) do
    %{
      response
      | "result" =>
          payload
          |> Map.put("resultType", "complete")
          |> Map.put("_meta", %{
            @server_info_meta_key => %{
              "name" => state.server_name,
              "version" => @server_version
            }
          })
    }
  end

  defp modernise(response, _state), do: response

  defp result(id, payload), do: %{"jsonrpc" => "2.0", "id" => id, "result" => payload}

  defp error(id, code, message) do
    %{"jsonrpc" => "2.0", "id" => id, "error" => %{"code" => code, "message" => message}}
  end
end
