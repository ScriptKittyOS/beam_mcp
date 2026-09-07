# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Server do
  alias BeamMCP.Schema

  @moduledoc """
  The protocol core: one message in, one response out, no process and no state of its own.

  `handle_message/2` takes a decoded JSON-RPC message and the state from `new/1`, and returns
  the next state and a response — or `nil` where the protocol defines no reply. A transport
  supplies the bytes; this module never touches them.

  ## Two eras

  It serves `2026-07-28` and `2025-11-25`, and tells them apart the way the specification says
  a dual-era server should: a request carrying per-request `_meta` is served statelessly, and
  an `initialize` request selects legacy semantics. `_meta` decides only the statelessness —
  the revision it *names* then decides the method table and the result envelope, so a request
  declaring `2025-11-25` through `_meta` gets that revision's semantics, not the modern ones.
  A request naming a revision it does not support gets `UnsupportedProtocolVersionError`
  (`-32022`) listing what it does.

  Two methods are matched before that switch and so are served identically at both eras:
  `server/discover`, which is the stdio era probe and must answer a client that does not yet
  know what it is talking to, and `initialize`, which selects legacy semantics whatever else
  it carries. Neither result is decorated.

  ## What the host supplies

      BeamMCP.Server.new(
        tool_catalog: MyApp.Catalog,        # required, a BeamMCP.ToolCatalog
        dispatch: &MyApp.Dispatch.call/3,   # required for tools/call
        server_name: "my-app"               # optional, defaults to "beam_mcp"
      )

  The server holds no catalog and executes nothing. It advertises the schema a tool's
  `BeamMCP.ToolSpec` carries and enforces that same schema on the call, so what a client is
  shown and what it is held to cannot drift apart.
  """

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
          tool_catalog: module(),
          tools_cache_scope: String.t(),
          tools_ttl_ms: non_neg_integer()
        }

  @spec new(keyword()) :: state()
  def new(opts \\ []) do
    %{
      dispatch: Keyword.get(opts, :dispatch),
      dispatch_opts: Keyword.get(opts, :dispatch_opts, []),
      initialized?: false,
      server_name: Keyword.get(opts, :server_name, @default_server_name),
      shutdown?: false,
      tool_catalog: Keyword.fetch!(opts, :tool_catalog),
      # 2026-07-28 requires ttlMs and cacheScope on tools/list results. Neither is the
      # package's to invent: ttlMs is a freshness hint about a catalog the host owns, and
      # cacheScope is a disclosure decision -- "public" lets shared intermediaries cache a
      # tool list, and a tool list can be sensitive. So both are supplied, and the default
      # is the NON-permissive one, because a package that picks the permissive default on a
      # host's behalf has made a disclosure decision it cannot keep.
      tools_ttl_ms: Keyword.get(opts, :tools_ttl_ms, 0),
      tools_cache_scope: Keyword.get(opts, :tools_cache_scope, "private")
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

  # A request carrying a _meta that NAMES A REVISION is served statelessly: no session,
  # whatever revision it names. A _meta that is not a map, or that carries no version key,
  # does not match this head at all and falls through to the handlers below.
  # Which revision it names then decides the method table and the result envelope,
  # because the spec requires every request to declare its version in _meta and requires the
  # server to serve or refuse *that* version. Both branches below are reachable: -32022 tells
  # a client to pick from `supported` -- which lists 2025-11-25 -- and retry the request,
  # so a _meta naming the legacy revision is a message this server asks clients to send.
  def handle_message(
        state,
        %{"jsonrpc" => "2.0", "id" => id, "_meta" => %{@version_meta_key => version}} = message
      ) do
    bare = Map.drop(message, ["_meta"])

    case version do
      @modern_version ->
        # ping was removed in 2026-07-28. The legacy handler below must not be inherited by a
        # request that declared the modern revision.
        if message["method"] == "ping" do
          {state, error(id, -32_601, "Method not found: ping")}
        else
          {next, response} = handle_message(state, bare)
          # `next`, not `state`: modernise/2 reads only server_name today, which nothing
          # mutates, so this is currently indistinguishable -- and would stop being so the
          # moment any handler changed a field modernise/2 reads.
          {next, modernise(response, next)}
        end

      @legacy_version ->
        # 2025-11-25 semantics: ping exists, and the result carries neither resultType nor
        # serverInfo _meta, both of which 2026-07-28 introduced.
        handle_message(state, bare)

      _other ->
        {state, unsupported_version(id, version)}
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

    # CacheableResult: 2026-07-28 requires both fields on tools/list. They are carried at
    # both eras rather than only the modern one -- 2025-11-25 permits any result structure,
    # so their presence is harmless there, while making them conditional would put a second
    # version-dependent branch in a clause that has already been the subject of one defect.
    {state,
     result(id, %{
       "tools" => tools,
       "ttlMs" => state.tools_ttl_ms,
       "cacheScope" => state.tools_cache_scope
     })}
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
