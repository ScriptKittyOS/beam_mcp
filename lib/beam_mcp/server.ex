# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Server do
  alias BeamMCP.Catalog
  alias BeamMCP.Schema
  alias BeamMCP.Stacktrace

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

  ## What it does not do: multi-round-trip requests

  `2026-07-28` lets a server answer `tools/call`, `resources/read` or `prompts/get` with an
  `InputRequiredResult` and continue on a later request carrying `inputResponses` and a
  `requestState`. This core does not: every request is answered completely or refused, the
  one `resultType` it writes is `"complete"`, and the two continuation parameters are read
  nowhere -- a request carrying them is served as if it carried neither, because nothing
  here ever asked for input. The reason is the first sentence of this page: no process, no
  state of its own; an input-required round trip is state between two messages, and the
  host that wants one owns exactly that state, above this core. Stated on the
  will-not-implement page (entry 12) with the census that holds it.

  ## What the host supplies

      BeamMCP.Server.new(
        catalog: MyApp.Catalog,             # required, a BeamMCP.Catalog
        dispatch: &MyApp.Dispatch.call/3,   # required for tools/call
        server_name: "my-app"               # optional, defaults to "beam_mcp"
      )

  The server holds no catalog and executes nothing. It advertises the schema a tool's
  `BeamMCP.ToolSpec` carries and enforces that same schema on the call, so what a client is
  shown and what it is held to cannot drift apart.
  """

  alias BeamMCP.Cursor
  alias BeamMCP.PromptArgument
  alias BeamMCP.PromptSpec
  alias BeamMCP.ResourceSpec
  alias BeamMCP.ResourceTemplateSpec
  alias BeamMCP.ToolSpec

  # Two revisions, two eras. 2026-07-28 removed the initialize handshake and protocol-level
  # sessions; 2025-11-25 and earlier open with initialize. The spec calls a server serving
  # both "dual-era" and fixes the discriminator: modern per-request _meta, or initialize.
  @modern_version "2026-07-28"

  @legacy_version "2025-11-25"
  @supported_versions [@modern_version, @legacy_version]

  @version_meta_key "io.modelcontextprotocol/protocolVersion"
  @capabilities_meta_key "io.modelcontextprotocol/clientCapabilities"
  @server_info_meta_key "io.modelcontextprotocol/serverInfo"
  @default_server_name "beam_mcp"
  # What the server advertises, in server/discover and in the initialize result: one literal,
  # so the two eras cannot disagree, and every key of it is served by a clause below --
  # advertising a capability the server does not serve is the defect class this package
  # names on the transport side, and the capability census holds the keys to the schema's.
  # `resources` and `prompts` are always present, as `tools` is: their methods are always
  # served, and an empty catalog answers an empty list. Neither `listChanged` nor `subscribe`
  # is offered: the server sends no notifications.
  @capabilities %{
    "tools" => %{"listChanged" => false},
    "resources" => %{"listChanged" => false, "subscribe" => false},
    "prompts" => %{"listChanged" => false}
  }
  # Read from the application spec rather than restated here. A hardcoded copy beside the one
  # in mix.exs is a transcription defect waiting for the first release that updates one of them.
  @server_version Mix.Project.config()[:version]

  @typedoc """
  The dispatch contract. A host supplies a function of this shape; the server calls it and
  never inspects what it does. Any three-arity function returning an ok-or-error tuple
  satisfies it, whatever sits behind it.
  """
  @type dispatch :: (atom(), map(), keyword() -> {:ok, term()} | {:error, term()})

  @type state :: %{
          dispatch: (atom(), map(), keyword() -> {:ok, term()} | {:error, term()}),
          dispatch_opts: keyword(),
          initialized?: boolean(),
          server_name: String.t(),
          shutdown?: boolean(),
          catalog: module(),
          supported_versions: [String.t(), ...],
          tools_cache_scope: String.t(),
          tools_ttl_ms: non_neg_integer(),
          resources_cache_scope: String.t(),
          resources_ttl_ms: non_neg_integer(),
          prompts_cache_scope: String.t(),
          prompts_ttl_ms: non_neg_integer(),
          page_size: pos_integer()
        }

  # Every option `new/1` accepts, with the shape it must have. Read as a table so that a
  # wrong option is refused HERE, by name, the way the catalog is -- not held and raised on
  # far from the call that supplied it (measured: a non-binary `server_name` was held, and
  # raised inside the connectome's id derivation at snapshot time). `:catalog` is in the
  # table for the unknown-key check; its shape is `Catalog.validate/1`'s.
  @options [
    catalog: "a module implementing the BeamMCP.Catalog behaviour",
    dispatch: "a function of three arguments, or absent",
    dispatch_opts: "a keyword list",
    server_name: "a string",
    supported_versions:
      "a non-empty list of the revisions this package implements, in the order to advertise them",
    tools_ttl_ms: "a non-negative integer",
    tools_cache_scope: "a string",
    resources_ttl_ms: "a non-negative integer",
    resources_cache_scope: "a string",
    prompts_ttl_ms: "a non-negative integer",
    prompts_cache_scope: "a string",
    page_size: "a positive integer"
  ]

  @default_page_size 50

  defp valid?(:catalog, value), do: is_atom(value)
  defp valid?(:dispatch, value), do: is_nil(value) or is_function(value, 3)
  defp valid?(:dispatch_opts, value), do: Keyword.keyword?(value)
  defp valid?(:server_name, value), do: is_binary(value)

  defp valid?(:supported_versions, value),
    do: is_list(value) and value != [] and Enum.all?(value, &(&1 in @supported_versions))

  defp valid?(:tools_ttl_ms, value), do: is_integer(value) and value >= 0
  defp valid?(:tools_cache_scope, value), do: is_binary(value)
  defp valid?(:resources_ttl_ms, value), do: is_integer(value) and value >= 0
  defp valid?(:resources_cache_scope, value), do: is_binary(value)
  defp valid?(:prompts_ttl_ms, value), do: is_integer(value) and value >= 0
  defp valid?(:prompts_cache_scope, value), do: is_binary(value)
  defp valid?(:page_size, value), do: is_integer(value) and value > 0

  @spec new(keyword()) :: state()
  def new(opts \\ []) do
    validate_options!(opts)

    %{
      dispatch: Keyword.get(opts, :dispatch),
      dispatch_opts: Keyword.get(opts, :dispatch_opts, []),
      initialized?: false,
      server_name: Keyword.get(opts, :server_name, @default_server_name),
      shutdown?: false,
      catalog: fetch_catalog!(opts),
      # The revisions this server ADVERTISES -- in server/discover and in -32022's `supported`.
      # The core implements both; a transport that serves one must say so (the HTTP transport
      # refuses 2025-11-25 on every POST, so it passes [2026-07-28]): advertising a revision
      # the transport will not serve is the opposite of honesty. Dual-era is a stdio fact.
      supported_versions: Keyword.get(opts, :supported_versions, @supported_versions),
      # 2026-07-28 requires ttlMs and cacheScope on tools/list results. Neither is the
      # package's to invent: ttlMs is a freshness hint about a catalog the host owns, and
      # cacheScope is a disclosure decision -- "public" lets shared intermediaries cache a
      # tool list, and a tool list can be sensitive. So both are supplied, and the default
      # is the NON-permissive one, because a package that picks the permissive default on a
      # host's behalf has made a disclosure decision it cannot keep.
      tools_ttl_ms: Keyword.get(opts, :tools_ttl_ms, 0),
      tools_cache_scope: Keyword.get(opts, :tools_cache_scope, "private"),
      # The same pair for the three resource results, with the same reasons and the same
      # non-permissive defaults.
      resources_ttl_ms: Keyword.get(opts, :resources_ttl_ms, 0),
      resources_cache_scope: Keyword.get(opts, :resources_cache_scope, "private"),
      # And for prompts/list (prompts/get is not cacheable: its result carries neither).
      prompts_ttl_ms: Keyword.get(opts, :prompts_ttl_ms, 0),
      prompts_cache_scope: Keyword.get(opts, :prompts_cache_scope, "private"),
      # The page size of every paginated list (`BeamMCP.Cursor`). The specification leaves
      # it to the server; a client walks `nextCursor` whatever it is.
      page_size: Keyword.get(opts, :page_size, @default_page_size)
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

  # WHERE _meta LIVES. `JSONRPCRequest` has no `_meta`; the request's `_meta` is
  # `params._meta` (`RequestParams`, required in 2026-07-28 with the protocol version and the
  # client capabilities inside it). Until 0.5.0 this package read the message's TOP LEVEL --
  # and its own tests sent it there -- so a spec-following stdio client's version went unread
  # and it was answered legacy-shaped while the server advertised modern. The top-level
  # position is not a compatibility mode: present, it is refused by name, whether or not
  # `params._meta` is there too, because two accepted shapes would be permanent and the wrong
  # one would quietly outlive the right one. This clause runs before every other so that no
  # method -- server/discover included -- is answered off a `_meta` in the wrong place.
  def handle_message(state, %{"jsonrpc" => "2.0", "id" => id, "_meta" => _}) do
    {state,
     error(
       id,
       -32_602,
       "Invalid params: _meta belongs in params._meta (2026-07-28 RequestParams), not at " <>
         "the top level of the request"
     )}
  end

  # A NOTIFICATION is never answered (JSON-RPC 2.0), so the position rule cannot refuse one:
  # a misplaced _meta on a notification is dropped and the notification is served as it would
  # be bare. Over HTTP the transport refuses the shape with 400 before this is reached.
  def handle_message(state, %{"jsonrpc" => "2.0", "_meta" => _} = notification)
      when not is_map_key(notification, "id") do
    handle_message(state, Map.delete(notification, "_meta"))
  end

  # server/discover is mandatory in 2026-07-28, and on stdio it doubles as the era probe: a
  # client sends it before it knows what it is talking to. So the CORE answers it whether or
  # not the request carries modern _meta -- the stdio exception. (The HTTP transport requires
  # a version on every POST and refuses a headerless one before this is reached: not an HTTP
  # exception.) The result is the schema's DiscoverResult: cacheScope, capabilities,
  # resultType, supportedVersions and ttlMs are all required, and serverInfo left the body
  # for the result's _meta in spec PR #3002. It was undecorated until 0.5.0 -- a probe
  # shortcut, and a result a client could read as legacy. ttlMs 0 and cacheScope "private"
  # because nothing here caches and the non-permissive default is the honest one.
  def handle_message(state, %{"jsonrpc" => "2.0", "id" => id, "method" => "server/discover"}) do
    {state,
     id
     |> result(%{
       "supportedVersions" => state.supported_versions,
       "capabilities" => @capabilities,
       "ttlMs" => 0,
       "cacheScope" => "private"
     })
     |> modernise(state)}
  end

  # An initialize request selects legacy semantics, whatever else it carries.
  def handle_message(state, %{"jsonrpc" => "2.0", "id" => id, "method" => "initialize"} = message) do
    requested = get_in(message, ["params", "protocolVersion"]) || @legacy_version

    if requested in state.supported_versions do
      response =
        result(id, %{
          "protocolVersion" => requested,
          "capabilities" => @capabilities,
          "serverInfo" => %{"name" => state.server_name, "version" => @server_version}
        })

      {%{state | initialized?: true}, response}
    else
      {state, unsupported_version(state, id, requested)}
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
        %{
          "jsonrpc" => "2.0",
          "id" => id,
          "params" => %{"_meta" => %{@version_meta_key => version} = meta}
        } =
          message
      ) do
    bare = %{message | "params" => Map.delete(message["params"], "_meta")}

    # A revision the server does not ADVERTISE is not served either, whatever the core could
    # do: the HTTP transport narrows the list to 2026-07-28 and refuses the rest by header
    # before this is reached; a host that narrows it on stdio gets the same refusal here.
    case if(version in state.supported_versions, do: version, else: :unadvertised) do
      @modern_version ->
        # ping was removed in 2026-07-28. The legacy handler below must not be inherited by a
        # request that declared the modern revision.
        cond do
          # RequestParams requires the client's capabilities beside the version: a modern
          # request without them is invalid params, named. (The version's own absence never
          # reaches here -- it is the clause head.)
          not Map.has_key?(meta, @capabilities_meta_key) ->
            {state,
             error(
               id,
               -32_602,
               "Invalid params: params._meta lacks io.modelcontextprotocol/clientCapabilities, " <>
                 "which 2026-07-28 requires on every request"
             )}

          message["method"] == "ping" ->
            {state, error(id, -32_601, "Method not found: ping")}

          true ->
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
        {state, unsupported_version(state, id, version)}
    end
  end

  # A params._meta that names no protocol version is not a legacy request; it is an invalid
  # one. (A legacy request either carries no _meta at all -- the initialize opener -- or names
  # 2025-11-25 in it.)
  def handle_message(state, %{
        "jsonrpc" => "2.0",
        "id" => id,
        "params" => %{"_meta" => %{} = meta}
      })
      when not is_map_key(meta, @version_meta_key) do
    {state,
     error(
       id,
       -32_602,
       "Invalid params: params._meta lacks io.modelcontextprotocol/protocolVersion"
     )}
  end

  # `params._meta` is any JSON value once `params` is an object; one that is not an object is
  # invalid params, not a legacy request. (`NotificationParams._meta` is optional and a
  # notification is never answered, so this is for requests.)
  def handle_message(state, %{"jsonrpc" => "2.0", "id" => id, "params" => %{"_meta" => meta}})
      when not is_map(meta) do
    {state, error(id, -32_602, "Invalid params: params._meta must be an object")}
  end

  def handle_message(state, %{"jsonrpc" => "2.0", "method" => "notifications/initialized"}) do
    {%{state | initialized?: true}, nil}
  end

  def handle_message(state, %{"jsonrpc" => "2.0", "id" => id, "method" => "ping"}) do
    {state, result(id, %{})}
  end

  def handle_message(state, %{"jsonrpc" => "2.0", "id" => id, "method" => "tools/list"}) do
    tools = state.catalog |> Catalog.tools() |> Enum.map(&tool_definition/1)

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

  # The two lists: one reader each (`Catalog.resources/1`, `Catalog.templates/1`), sorted on
  # the key the cursor names, paged by the shared codec. A cursor from the other list, or from
  # anywhere else, is invalid params by name -- never a silently wrong page.
  def handle_message(state, %{"jsonrpc" => "2.0", "id" => id, "method" => "resources/list"} = m) do
    paginated(state, id, m, %{
      kind: :resources,
      key: "resources",
      items: Catalog.resources(state.catalog),
      key_fun: & &1.uri,
      definition: &resource_definition/1,
      cache: {state.resources_ttl_ms, state.resources_cache_scope}
    })
  end

  def handle_message(state, %{"jsonrpc" => "2.0", "id" => id, "method" => "prompts/list"} = m) do
    paginated(state, id, m, %{
      kind: :prompts,
      key: "prompts",
      items: Catalog.prompts(state.catalog),
      key_fun: & &1.name,
      definition: &prompt_definition/1,
      cache: {state.prompts_ttl_ms, state.prompts_cache_scope}
    })
  end

  # A prompt is rendered only for a name the same reader lists; its arguments go through the
  # tools validator over the schema derived from the declared argument list, and reach the
  # reader keyed by the declared names -- the one path a tool's arguments take.
  def handle_message(
        state,
        %{"jsonrpc" => "2.0", "id" => id, "method" => "prompts/get", "params" => params}
      ) do
    case params do
      %{"name" => name} when is_binary(name) ->
        {state, get_prompt(state, id, name, Map.get(params, "arguments", %{}))}

      _ ->
        {state, error(id, -32_602, "Invalid params: prompts/get requires a string name")}
    end
  end

  def handle_message(state, %{"jsonrpc" => "2.0", "id" => id, "method" => "prompts/get"}) do
    {state, error(id, -32_602, "Invalid params: prompts/get requires a string name")}
  end

  def handle_message(
        state,
        %{"jsonrpc" => "2.0", "id" => id, "method" => "resources/templates/list"} = m
      ) do
    paginated(state, id, m, %{
      kind: :resource_templates,
      key: "resourceTemplates",
      items: Catalog.templates(state.catalog),
      key_fun: & &1.uri_template,
      definition: &template_definition/1,
      cache: {state.resources_ttl_ms, state.resources_cache_scope}
    })
  end

  # A read is served only for a uri the same reader lists or a listed template matches; the
  # refusal comes before the reader runs, so what is advertised and what is readable cannot
  # drift. The handler answers -32002, 2025-11-25's not-found code; the modern path renames
  # it to -32602, 2026-07-28's (see modernise/2). The read itself is the catalog's.
  def handle_message(
        state,
        %{"jsonrpc" => "2.0", "id" => id, "method" => "resources/read", "params" => params}
      ) do
    case params do
      %{"uri" => uri} when is_binary(uri) ->
        {state, read_resource(state, id, uri)}

      _ ->
        {state, error(id, -32_602, "Invalid params: resources/read requires a string uri")}
    end
  end

  # The schema requires params on the request; a resources/read with none is invalid params,
  # not an unknown method.
  def handle_message(state, %{"jsonrpc" => "2.0", "id" => id, "method" => "resources/read"}) do
    {state, error(id, -32_602, "Invalid params: resources/read requires a string uri")}
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

  # One paginated list: `list` names the kind (the cursor's), the result key, the sorted
  # items, the key function, the per-item definition and the ttl/scope pair.
  defp paginated(state, id, message, list) do
    case position(list.kind, cursor_param(message)) do
      {:ok, position} ->
        {page, next} = Cursor.page(list.kind, list.items, list.key_fun, position, state.page_size)
        {ttl, scope} = list.cache

        payload =
          %{list.key => Enum.map(page, list.definition), "ttlMs" => ttl, "cacheScope" => scope}
          |> put_present("nextCursor", next)

        {state, result(id, payload)}

      {:error, why} ->
        {state, error(id, -32_602, "Invalid params: " <> why)}
    end
  end

  # The cursor, read by pattern: JSON-RPC lets params be an array, and a non-object params
  # must be refused by name, never reached into (the class the HTTP transport recorded on
  # its side: a non-map params raised in Access.get/3).
  defp cursor_param(%{"params" => %{"cursor" => cursor}}), do: cursor
  defp cursor_param(%{"params" => %{}}), do: nil
  defp cursor_param(%{"params" => _other}), do: :not_an_object
  defp cursor_param(_message), do: nil

  defp position(_kind, nil), do: {:ok, nil}
  defp position(_kind, :not_an_object), do: {:error, "params must be an object"}

  # The wire's own bytes are never echoed: a foreign cursor's kind is whatever a client put
  # there, of any length.
  defp position(kind, cursor) do
    case Cursor.decode(kind, cursor) do
      {:ok, key} -> {:ok, {:ok, key}}
      {:error, :malformed} -> {:error, "cursor is malformed"}
      {:error, {:kind, _other}} -> {:error, "cursor belongs to another list, not #{kind}"}
    end
  end

  defp read_resource(state, id, uri) do
    catalog = state.catalog

    if Catalog.readable?(catalog, uri) do
      answer_read(state, id, uri, catalog.read_resource(uri))
    else
      error(id, -32_002, "Resource not found: #{uri}", %{"uri" => uri})
    end
  end

  # The reader's answer to the wire. Only the shape is the package's: a list of contents
  # items is encoded; an error is the not-found code (-32002 here, renamed to -32602 on the
  # modern path) with the reason; anything else is a defect named.
  defp answer_read(state, id, _uri, {:ok, contents}) when is_list(contents) do
    case Enum.reduce_while(contents, {:ok, []}, &encode_contents/2) do
      {:ok, encoded} ->
        result(id, %{
          "contents" => Enum.reverse(encoded),
          "ttlMs" => state.resources_ttl_ms,
          "cacheScope" => state.resources_cache_scope
        })

      {:error, defect} ->
        error(id, -32_603, "Internal error: #{inspect(state.catalog)}.read_resource/1 " <> defect)
    end
  end

  defp answer_read(_state, id, uri, {:error, reason}) do
    error(id, -32_002, "Resource not found: #{uri}", %{
      "uri" => uri,
      "reason" => to_json_value(reason)
    })
  end

  defp answer_read(state, id, _uri, other) do
    error(
      id,
      -32_603,
      "Internal error: #{inspect(state.catalog)}.read_resource/1 answered #{inspect(other)}, " <>
        "not {:ok, contents} or {:error, reason}"
    )
  end

  defp get_prompt(state, id, name, arguments) do
    catalog = state.catalog

    with {:ok, %PromptSpec{} = spec} <- fetch_prompt(catalog, name),
         {:ok, args} <- prompt_arguments(spec, arguments) do
      answer_prompt(id, name, catalog, catalog.get_prompt(name, args))
    else
      {:unknown, name} ->
        error(id, -32_602, "Invalid params: unknown prompt #{name}", %{"name" => name})

      {:invalid, reason} ->
        error(id, -32_602, "Invalid params: #{reason}", %{"name" => name, "reason" => reason})
    end
  end

  defp fetch_prompt(catalog, name) do
    case Catalog.fetch_prompt(catalog, name) do
      {:ok, spec} -> {:ok, spec}
      :error -> {:unknown, name}
    end
  end

  # The tools path, exactly: the derived schema through Schema.validate/2, then the keys
  # normalised to the DECLARED names -- a caller's key that is not declared was refused by
  # the schema and never reaches String.to_atom/1.
  defp prompt_arguments(%PromptSpec{} = spec, arguments) do
    schema = PromptSpec.argument_schema(spec)

    case Schema.validate(arguments, schema) do
      :ok -> {:ok, normalize_arguments(arguments, schema)}
      {:error, reason} -> {:invalid, "invalid arguments: #{reason}"}
    end
  end

  defp answer_prompt(id, _name, catalog, {:ok, %{messages: messages} = rendered})
       when is_list(messages) do
    case Enum.reduce_while(messages, {:ok, []}, &encode_message/2) do
      {:ok, encoded} ->
        result(
          id,
          put_present(
            %{"messages" => Enum.reverse(encoded)},
            "description",
            rendered[:description]
          )
        )

      {:error, defect} ->
        error(id, -32_603, "Internal error: #{inspect(catalog)}.get_prompt/2 " <> defect)
    end
  end

  defp answer_prompt(id, name, _catalog, {:error, reason}) do
    error(id, -32_602, "Invalid params: prompt #{name} cannot be rendered", %{
      "name" => name,
      "reason" => to_json_value(reason)
    })
  end

  defp answer_prompt(id, _name, catalog, other) do
    error(
      id,
      -32_603,
      "Internal error: #{inspect(catalog)}.get_prompt/2 answered #{inspect(other)}, " <>
        "not {:ok, %{messages: ...}} or {:error, reason}"
    )
  end

  # One message as the reader gives it, to the wire's PromptMessage: a role of the two the
  # schema names, and text content.
  defp encode_message(%{role: role, text: text}, {:ok, acc})
       when role in [:user, :assistant] and is_binary(text) do
    {:cont,
     {:ok,
      [
        %{"role" => Atom.to_string(role), "content" => %{"type" => "text", "text" => text}}
        | acc
      ]}}
  end

  defp encode_message(message, _acc),
    do:
      {:halt,
       {:error,
        "returned a message without a role of :user or :assistant and a string :text: " <>
          inspect(message)}}

  defp prompt_definition(%PromptSpec{} = p) do
    %{"name" => p.name}
    |> put_present("title", p.title)
    |> put_present("description", p.description)
    |> put_present("icons", p.icons)
    |> put_present(
      "arguments",
      if(p.arguments == [], do: nil, else: Enum.map(p.arguments, &argument_definition/1))
    )
  end

  defp argument_definition(%PromptArgument{} = a) do
    %{"name" => a.name, "required" => a.required}
    |> put_present("title", a.title)
    |> put_present("description", a.description)
  end

  # One contents item as the reader gives it, to the wire's shape: `text` as is, `blob` as
  # base64; a uri required; both or neither of text/blob a defect named, never reshaped.
  defp encode_contents(%{uri: uri} = item, {:ok, acc}) when is_binary(uri) do
    case {Map.get(item, :text), Map.get(item, :blob)} do
      {text, nil} when is_binary(text) ->
        {:cont, {:ok, [contents_item(uri, item, "text", text) | acc]}}

      {nil, blob} when is_binary(blob) ->
        {:cont, {:ok, [contents_item(uri, item, "blob", Base.encode64(blob)) | acc]}}

      _ ->
        {:halt, {:error, "returned an item with neither or both of :text and :blob for #{uri}"}}
    end
  end

  defp encode_contents(item, _acc),
    do: {:halt, {:error, "returned an item without a string :uri: #{inspect(item)}"}}

  defp contents_item(uri, item, key, value) do
    %{"uri" => uri, key => value} |> put_present("mimeType", Map.get(item, :mime_type))
  end

  defp resource_definition(%ResourceSpec{} = r) do
    %{"uri" => r.uri, "name" => r.name}
    |> put_present("title", r.title)
    |> put_present("description", r.description)
    |> put_present("mimeType", r.mime_type)
    |> put_present("size", r.size)
    |> put_present("annotations", r.annotations)
    |> put_present("icons", r.icons)
  end

  defp template_definition(%ResourceTemplateSpec{} = t) do
    %{"uriTemplate" => t.uri_template, "name" => t.name}
    |> put_present("title", t.title)
    |> put_present("description", t.description)
    |> put_present("mimeType", t.mime_type)
    |> put_present("annotations", t.annotations)
    |> put_present("icons", t.icons)
  end

  # An optional field the specification leaves out is left out, never sent as null.
  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)

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
  # it, and the spec it returns carries the schema that will be enforced. Both this and the
  # advertisement above go through `Catalog.tools/1`, so there is one reader rather than two
  # call sites that could drift apart.
  defp find_tool(state, name), do: Catalog.fetch(state.catalog, name)

  # THE SHAPE IS REFUSED HERE, not at the first request. `new/1` is runtime, so calling the
  # host's `capabilities/0` is safe -- unlike `Transport.HTTP.init/1`, which under Plug's
  # default init_mode is the host's COMPILE time. Same pattern as `:authorize`: a host that
  # mis-wires this learns when it starts, not from a BadMapError in a request path.
  defp validate_options!(opts) do
    unless Keyword.keyword?(opts) do
      raise ArgumentError, "BeamMCP.Server.new/1 takes a keyword list, got: #{inspect(opts)}"
    end

    Enum.each(opts, &validate_option!/1)
  end

  defp validate_option!({key, value}) do
    case Keyword.fetch(@options, key) do
      {:ok, shape} ->
        valid?(key, value) ||
          raise ArgumentError,
                "BeamMCP.Server.new/1: #{inspect(key)} must be #{shape}, got: #{inspect(value)}"

      :error ->
        raise ArgumentError,
              "BeamMCP.Server.new/1 does not take #{inspect(key)}; the options are " <>
                Enum.map_join(Keyword.keys(@options), ", ", &inspect/1)
    end
  end

  defp fetch_catalog!(opts) do
    catalog = Keyword.fetch!(opts, :catalog)

    case Catalog.validate(catalog) do
      :ok ->
        catalog

      {:error, reason} ->
        raise ArgumentError, """
        BeamMCP.Server requires a :catalog implementing the BeamMCP.Catalog behaviour.

        #{reason}

        capabilities/0 must return a map with all three keys; resources and prompts may be
        empty, but an absent key is a malformed catalog rather than an empty one:

            %{tools: [%BeamMCP.ToolSpec{}], resources: [], prompts: []}
        """
    end
  end

  # The advertised schema is the contract. Validate the wire form -- string keys, as the
  # client sent them -- before normalising, so `required` and `additionalProperties`
  # mean what tools/list says they mean.
  defp validate_and_dispatch(state, %ToolSpec{} = spec, arguments) do
    case Schema.validate(arguments, spec.input_schema) do
      :ok ->
        args = normalize_arguments(arguments, spec.input_schema)
        dispatch(state, spec, args)

      {:error, reason} ->
        {:error,
         %{"tool" => Atom.to_string(spec.name), "reason" => "invalid arguments: #{reason}"}}
    end
  end

  # The one site that emits `[:beam_mcp, :dispatch, :start | :stop | :exception]`. The
  # metadata is the edge's identity -- the server's name and the tool's -- and nothing the
  # call carried: no arguments, no result, no headers. `:exception` is `:telemetry.span/3`'s
  # shape with one difference: the stacktrace's frames carry arities, never argument lists.
  # The BEAM puts the arguments in the top frame of a function_clause or a BIF error, so
  # span/3's own catch would have handed every handler the call's arguments; the reason is
  # still the host's, verbatim, and the host's stacktrace is re-raised untouched. A
  # validation failure never reaches here: it is not a dispatch, and it is not an edge.
  defp dispatch(state, %ToolSpec{name: tool}, args) do
    meta = %{server_name: state.server_name, tool: tool, telemetry_span_context: make_ref()}
    start = System.monotonic_time()

    :telemetry.execute(
      [:beam_mcp, :dispatch, :start],
      %{system_time: System.system_time(), monotonic_time: start},
      meta
    )

    try do
      result = state.dispatch.(tool, args, state.dispatch_opts)
      stop = System.monotonic_time()

      :telemetry.execute(
        [:beam_mcp, :dispatch, :stop],
        %{duration: stop - start, monotonic_time: stop},
        Map.put(meta, :outcome, outcome(result))
      )

      result
    catch
      kind, reason ->
        stacktrace = __STACKTRACE__
        stop = System.monotonic_time()

        :telemetry.execute(
          [:beam_mcp, :dispatch, :exception],
          %{duration: stop - start, monotonic_time: stop},
          Map.merge(meta, %{
            kind: kind,
            reason: reason,
            stacktrace: Stacktrace.arities(stacktrace)
          })
        )

        :erlang.raise(kind, reason, stacktrace)
    end
  end

  defp outcome({:ok, _}), do: :ok
  defp outcome(_), do: :error

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
  # A tuple is a JSON array: a host's {:error, {:missing, :window}} reaches the client as
  # ["missing", "window"] rather than meeting an encoder with no clause for it (measured: the
  # request crashed before this clause existed).
  defp to_json_value(value) when is_tuple(value), do: value |> Tuple.to_list() |> to_json_value()
  defp to_json_value(value) when is_atom(value), do: Atom.to_string(value)
  defp to_json_value(value), do: value

  defp unsupported_version(state, id, requested) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "error" => %{
        "code" => -32_022,
        "message" => "Unsupported protocol version",
        "data" => %{"supported" => state.supported_versions, "requested" => requested}
      }
    }
  end

  # 2026-07-28 requires resultType on every result, and servers SHOULD identify themselves in
  # each result's _meta. Applied only on the modern path: a legacy result carries neither.
  #
  # The same path renames one error: a resource that does not exist is -32002 under
  # 2025-11-25 and MUST be -32602 under 2026-07-28 ("clients SHOULD also accept -32002 as a
  # resource not found error, as earlier protocol versions used this code"). The handler
  # answers the legacy code; the era that requires the other one is the era this function
  # already serves, so the rename lives here and nowhere else.
  defp modernise(%{"error" => %{"code" => -32_002} = e} = response, _state),
    do: %{response | "error" => %{e | "code" => -32_602}}

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

  defp error(id, code, message, data) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "error" => %{"code" => code, "message" => message, "data" => data}
    }
  end
end
