# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

# `plug` and `bandit` are optional dependencies, and `optional: true` governs dependency
# RESOLUTION, not compilation. Without this guard, `import Plug.Conn` is a hard compile error
# for every consumer that does not have Plug -- which is every stdio-only host, i.e. every
# 0.2.0 consumer upgrading. A lane caught it by building the package with the optional deps
# removed: the package did not compile at all, while the README and CHANGELOG inside the
# tarball claimed it would.
if Code.ensure_loaded?(Plug) do
  defmodule BeamMCP.Transport.HTTP do
    @moduledoc """
    Stateless Streamable HTTP transport: a `Plug` serving `2026-07-28` at one endpoint.

    A second caller of `BeamMCP.Server.handle_message/2`, which this module does not change.
    Every request stands alone — **no sessions, no `Mcp-Session-Id`, no SSE resumability**,
    all three removed from the transport in `2026-07-28`.

    Available only when `plug` is present. `plug` and `bandit` are optional dependencies, so a
    stdio-only host does not pull an HTTP server into its tree and this module simply does not
    exist there.

    ## Two options with no defaults, and why

    The package cannot decide who may call it: it has no view of a host's identity model, and
    deciding on the host's behalf would be claiming something it cannot keep. But a Plug that
    serves `tools/call` to anyone who can reach the port is a confused-deputy surface, and
    "the host should have authenticated" is documentation rather than a control.

    So both decisions are **required options with no defaults**. A host that omits either gets
    an `ArgumentError` when the Plug is initialised:

      * `:authorize` — `(Plug.Conn.t() -> :ok | {:error, term()})`, called before any message
        is handled. Whatever it returns as a reason goes to the log, never to the caller.
      * `:allowed_origins` — `[String.t()]` or `:any`. The specification makes validating
        `Origin` a MUST, to prevent DNS rebinding; which origins are legitimate is host
        knowledge. `:any` must be chosen explicitly.

    A required argument with no default is a contract, because a host cannot start without
    answering it.

    > #### Init-time, with one caveat {: .info}
    >
    > The check runs in `init/1`. Under Plug's default compile-time initialisation that is
    > build time; a host using `init_mode: :runtime` gets it on first request instead. The
    > guarantee is "before any message is handled", which holds in both.

    ## What it enforces

    The list lives in **one place**: the README's "What of `2026-07-28` this transport
    implements" section, which `test/beam_mcp/readme_claims_test.exs` pins. A copy of it stood
    here until a round-3 lane found it stale -- the CHANGELOG's copy of the same table was
    updated in the same diff that left this one behind, so the package shipped two enforcement
    tables that disagreed, and the one in the code was the wrong one.

    In summary, and deliberately without the detail that would make this a third copy: every
    standard header the revision requires is required and validated against the body, in **all**
    of a header's values rather than the first; `Mcp-Param-{Name}` is validated against the
    parameters the tool's own schema marks with `x-mcp-header`; refusals are `400` with `-32020`
    (`-32022` for an unsupported version); a bad `Origin` is `403`; a non-POST is `405`; an
    unimplemented method is `404`; and an unknown *tool* is `200` carrying a JSON-RPC error,
    because the endpoint is there and the argument was wrong.

    `Mcp-Method` and `Mcp-Name` are validated against the body because the specification says
    why: a load balancer may route on the header while the server executes the body.

    ## Usage

        Bandit.child_spec(
          plug: {BeamMCP.Transport.HTTP,
                 tool_catalog: MyApp.Catalog,
                 dispatch: &MyApp.Dispatch.call/3,
                 authorize: &MyApp.Auth.check/1,
                 allowed_origins: ["https://app.example.com"]},
          port: 4000,
          ip: {127, 0, 0, 1}
        )

    The specification says a locally-running server **SHOULD** bind to localhost rather than
    all interfaces. That is the host's `Bandit` option above; this module cannot enforce it.
    """

    @behaviour Plug

    import Plug.Conn

    require Logger

    alias BeamMCP.Server
    alias BeamMCP.ToolCatalog

    @modern_version "2026-07-28"
    @version_meta_key "io.modelcontextprotocol/protocolVersion"
    @protocol_header "mcp-protocol-version"

    # 1 MiB of decoded body. Without a cap, a request body is an unbounded allocation an
    # unauthenticated caller controls.
    @max_body_bytes 1_048_576
    @method_not_found "Method not found:"

    # Removed from the protocol by 2026-07-28: the stateless change deleted the handshake
    # ("make MCP stateless: remove the initialize / notifications/initialized handshake") and
    # SEP-2575 deleted ping.
    #
    # This lives in the TRANSPORT and not in the core on purpose. The core is dual-era and its
    # `initialize` clause deliberately outranks `_meta`, because over stdio an initialize IS the
    # era discriminator -- that rule is documented and stdio hosts depend on it. Over HTTP there
    # is no such choice to make: this Plug stamps every request `2026-07-28`, so a method that
    # revision does not have is not found here, whatever the core would do with it on another
    # carrier. Before this, `initialize` over HTTP was answered 200 with
    # `protocolVersion: "2025-11-25"` -- a caller declaring the modern revision handed a
    # different revision's version number, while the README said it was not implemented.
    @removed_in_modern ["ping", "initialize", "notifications/initialized"]

    # This Plug's own options; everything else in the keyword list belongs to Server.new/1.
    # Derived by exclusion rather than by naming what to keep: a `Keyword.take` list silently
    # dropped `tools_ttl_ms` and `tools_cache_scope` when they were added, and a test caught it.
    @plug_opts [:authorize, :allowed_origins]

    @impl Plug
    def init(opts) do
      authorize = Keyword.get(opts, :authorize)

      unless is_function(authorize, 1) do
        raise ArgumentError, """
        BeamMCP.Transport.HTTP requires an :authorize option, and it has no default.

        It must be a 1-arity function taking a Plug.Conn and returning :ok or {:error, reason}.

        This package cannot decide who may call your tools -- it has no view of your identity
        model -- but it will not serve tools/call to anyone who can reach the port either.
        Deciding is yours; not deciding is not an option this Plug offers.

        To accept every caller, say so explicitly:

            authorize: fn _conn -> :ok end
        """
      end

      origins = Keyword.get(opts, :allowed_origins)

      unless origins == :any or (is_list(origins) and Enum.all?(origins, &is_binary/1)) do
        raise ArgumentError, """
        BeamMCP.Transport.HTTP requires an :allowed_origins option, and it has no default.

        The specification makes validating the Origin header a MUST, to prevent DNS rebinding
        attacks. Which origins are legitimate is something only you know.

            allowed_origins: ["https://app.example.com"]
            allowed_origins: :any    # explicit, and a decision you are making
        """
      end

      catalog = Keyword.get(opts, :tool_catalog)

      # Checked for the behaviour, not for truthiness: `tool_catalog: true` passed the old check
      # and failed later, at the first tools/list, as an UndefinedFunctionError from inside the
      # request path. An option contract that only rejects `nil` moves the error to a worse
      # place rather than preventing it.
      # `Code.ensure_compiled/1`, not `ensure_loaded?/1`: a host whose catalog module lives in
      # the same project has not been loaded when its own supervision tree is being built, so
      # `ensure_loaded?` raised ArgumentError at build time naming a perfectly valid catalog.
      # An option contract that rejects correct configurations is worse than the truthiness
      # check it replaced.
      unless is_atom(catalog) and catalog != nil and
               match?({:module, _}, Code.ensure_compiled(catalog)) and
               function_exported?(catalog, :all, 0) do
        raise ArgumentError, """
        BeamMCP.Transport.HTTP requires a :tool_catalog option: a module implementing the
        BeamMCP.ToolCatalog behaviour, that is, exporting all/0.

        Got: #{inspect(catalog)}
        """
      end

      %{
        authorize: authorize,
        allowed_origins: origins,
        server_opts: Keyword.drop(opts, @plug_opts)
      }
    end

    @impl Plug
    def call(%Plug.Conn{} = conn, opts) do
      handle(conn, opts)
    rescue
      exception ->
        # An exception carrying a status is the SERVER SIGNALLING, not a fault: Bandit raises
        # Bandit.HTTPError with plug_status :request_timeout for a read timeout and
        # :bad_request for a malformed transfer coding, and its own pipeline turns that into
        # the response. Catching it turned a 408 into a 500, a 400 into a 500, and every
        # stalled connection into an unauthenticated 5xx with an error-level stacktrace -- a
        # regression this rescue introduced by widening to cover the crash class.
        #
        # The test is Plug.Exception.status/1, Plug's own protocol, which reads any exception's
        # :plug_status field. It therefore holds for adapters other than Bandit and needs no
        # reference to a module that may not be loaded. 500 means "carries no status of its
        # own", which is the only case this transport should be answering for.
        fault_response(conn, exception, __STACKTRACE__, nil)
    catch
      kind, reason ->
        Logger.error(Exception.format(kind, reason, __STACKTRACE__))
        crash_response(conn)
    end

    # The rescue wraps the WHOLE request path, not just dispatch.
    #
    # It used to wrap `do_dispatch/3` alone, and two lanes independently walked in through the
    # gap: a non-map `params` raised in `Access.get/3`, a non-string body value raised in
    # `String.Chars`, and non-UTF-8 header bytes raised in `Jason.EncodeError` -- each landing
    # on the bare empty 500 this module exists to avoid, one of them returning no response at
    # all. Every one was in code added by the commit that fixed the *first* instance of the
    # same shape, three functions away.
    #
    # Guarding the fields the lanes found would fix those inputs. Guarding the path fixes the
    # class, including whatever nobody has thought of yet -- which is the point, because the
    # inputs are attacker-chosen and the list of them is not knowable.
    defp handle(conn, opts) do
      with {:ok, conn} <- check_origin(conn, opts.allowed_origins),
           {:ok, conn} <- check_method(conn),
           {:ok, conn} <- authorize(conn, opts.authorize),
           {:ok, body, conn} <- read_body_bounded(conn),
           {:ok, conn, message} <- decode(conn, body),
           {:ok, conn} <- check_headers(conn, message, opts) do
        dispatch(conn, message, opts)
      else
        # Every step returns the conn it was handed, and every refusal answers on THAT conn.
        # `with/else` cannot see bindings made inside the `with`, so an earlier version
        # answered on the pre-`read_body` conn and Bandit framed the next request's bytes as
        # this one's unread body. Size-dependent, so every small test passed.
        {:refused, conn, status, payload} -> send_json(conn, status, payload)
      end
    end

    # Answering a crash must not itself crash: the payload is a constant, so there is nothing
    # in it that can fail to encode.
    # An exception carrying a status is the SERVER SIGNALLING, not a fault: Bandit raises
    # Bandit.HTTPError with plug_status :request_timeout for a read timeout and :bad_request
    # for a malformed transfer coding, and its own pipeline turns that into the response.
    # Catching it turned a 408 into a 500, a 400 into a 500, and every stalled connection into
    # an unauthenticated 5xx with an error-level stacktrace -- a regression introduced by
    # widening the rescue to cover the crash class, and measured against the previous commit
    # rather than argued.
    #
    # The test is Plug.Exception.status/1, Plug's own protocol, which reads any exception's
    # :plug_status. It therefore holds for adapters other than Bandit and needs no reference to
    # a module that may not be loaded. 500 means "carries no status of its own", which is the
    # only case this transport should be answering for.
    defp fault_response(conn, exception, stacktrace, id) do
      if Plug.Exception.status(exception) == 500 do
        Logger.error(Exception.format(:error, exception, stacktrace))
        send_json(conn, 500, error(id, -32_603, "Internal error"))
      else
        reraise exception, stacktrace
      end
    end

    defp crash_response(conn) do
      send_json(conn, 500, %{
        "jsonrpc" => "2.0",
        "id" => nil,
        "error" => %{"code" => -32_603, "message" => "Internal error"}
      })
    end

    # -- the spec's MUSTs, in the order a request meets them ---------------------------------

    # "Servers MUST validate the Origin header on all incoming connections to prevent DNS
    # rebinding attacks. If the Origin header is present and invalid, servers MUST respond
    # with HTTP 403 Forbidden." An absent Origin is not an invalid one -- non-browser clients
    # send none -- so absence passes and presence is checked.
    #
    # EVERY Origin header is checked, not the first. A lane sent a good one followed by a bad
    # one and got 200 with tools/call executed; reversed, 403. Order-dependent validation is
    # not validation, and intermediaries do merge and append this header.
    defp check_origin(conn, :any), do: {:ok, conn}

    defp check_origin(conn, allowed) do
      case header_values(conn, "origin") do
        [] ->
          {:ok, conn}

        origins ->
          if Enum.all?(origins, &(&1 in allowed)),
            do: {:ok, conn},
            else: {:refused, conn, 403, error(nil, -32_600, "Origin not allowed")}
      end
    end

    # "The client MUST use HTTP POST to send JSON-RPC messages."
    defp check_method(%Plug.Conn{method: "POST"} = conn), do: {:ok, conn}

    defp check_method(conn) do
      {:refused, put_resp_header(conn, "allow", "POST"), 405,
       error(nil, -32_600, "Method not allowed: #{conn.method}; use POST")}
    end

    # The host decides who may call. What it returns MUST NOT reach the caller: an earlier
    # version interpolated `inspect(reason)` into the 403 body, and a lane recovered a planted
    # bearer token and database URL from it -- pre-authentication, on the one branch that is
    # by definition unauthenticated. The reason goes to the log, where the host can see it.
    defp authorize(conn, authorize_fun) do
      case authorize_fun.(conn) do
        :ok ->
          {:ok, conn}

        {:error, reason} ->
          Logger.info(fn -> "beam_mcp: refused by host authorize/1: #{inspect(reason)}" end)
          {:refused, conn, 403, error(nil, -32_600, "Forbidden")}

        other ->
          # A host returning neither :ok nor {:error, _} has a bug. Fail closed and log it,
          # rather than crashing with a WithClauseError and a bare 500.
          Logger.error(fn ->
            "beam_mcp: authorize/1 must return :ok or {:error, reason}, got: #{inspect(other)}"
          end)

          {:refused, conn, 403, error(nil, -32_600, "Forbidden")}
      end
    end

    defp read_body_bounded(conn) do
      case read_body(conn, length: @max_body_bytes) do
        {:ok, body, conn} ->
          {:ok, body, conn}

        {:more, _partial, conn} ->
          {:refused, close_after(conn), 413,
           error(nil, -32_600, "Request body exceeds #{@max_body_bytes} bytes")}

        {:error, reason} ->
          {:refused, conn, 400,
           error(nil, -32_700, "Could not read request body: #{inspect(reason)}")}
      end
    end

    defp decode(conn, "") do
      {:refused, conn, 400, error(nil, -32_700, "Parse error: empty body")}
    end

    defp decode(conn, body) do
      case Jason.decode(body) do
        {:ok, %{} = message} ->
          {:ok, conn, message}

        {:ok, other} ->
          {:refused, conn, 400,
           error(nil, -32_600, "Expected a JSON object, got #{type_of(other)}")}

        {:error, _} ->
          {:refused, conn, 400, error(nil, -32_700, "Parse error: body is not valid JSON")}
      end
    end

    # -- header validation ------------------------------------------------------------------
    #
    # "Servers that process the request body MUST reject requests where the values specified in
    # the headers do not match the corresponding values in the request body. This prevents
    # potential security vulnerabilities when different components in the network rely on
    # different sources of truth (e.g., a load balancer routing on the header value while the
    # MCP server executes based on the body value)."
    #
    # Two derivations, and getting the second one wrong is what round 3 found.
    #
    # WHICH HEADERS ARE READ is derived from the code: `header_values/2` is the only caller of
    # `get_req_header/2`, and every comparison is `Enum.all?` over all values. A header whose
    # first value satisfies this server while a later one is what the hop in front routes on is
    # the smuggling the text above exists to stop, and the first version of this module read
    # only the first value of four headers.
    #
    # WHICH MIRRORED PARAMETERS ARE REQUIRED is derived from the tool's `inputSchema`, NOT from
    # the headers the caller happened to send. Deriving it from the request looked like the
    # same "derive the population" move and is the opposite of it: the spec's fourth
    # server-behaviour row is "client omits header but value is in body -> server MUST reject",
    # which is unenforceable if the caller's own headers define the set. Omitting
    # `Mcp-Param-Region` while the body carried `region` returned 200 and dispatched.
    defp header_values(conn, name), do: get_req_header(conn, name)

    # "For headers that permit the Base64 sentinel encoding (Mcp-Name and Mcp-Param-{Name}),
    # servers MUST decode encoded values before comparing them to the body value."
    #
    # THAT SET AND NO OTHER. Decoding it everywhere let `Mcp-Method: =?base64?dG9vbHMvY2FsbA==?=`
    # satisfy this server while a gateway filtering on `Mcp-Method` saw an opaque token -- the
    # fix for one MUST reopening the exact hole the other MUST closes.
    defp decodable?("mcp-name"), do: true
    defp decodable?("mcp-param-" <> _), do: true
    defp decodable?(_name), do: false

    defp decode_header_value(name, value) do
      with true <- decodable?(name),
           "=?base64?" <> rest <- value,
           [encoded, ""] <- String.split(rest, "?=", parts: 2),
           {:ok, decoded} <- Base.decode64(encoded),
           # Base.decode64/1 accepts non-canonical trailing bits, so `ZWNobw==`, `ZWNobx==`,
           # `ZWNoby==` and `ZWNobz==` all decode to "echo" -- four spellings of one value, and
           # a hop comparing bytes disagrees with a server comparing decoded values. Re-encoding
           # and requiring the round trip admits exactly one.
           ^encoded <- Base.encode64(decoded) do
        decoded
      else
        _ -> value
      end
    end

    # "When validating integer parameter values, servers SHOULD compare the header value and the
    # body value numerically rather than as strings (e.g., `42.0` and `42` are considered
    # equal)." String comparison refused a conforming client that wrote the number differently.
    defp value_matches?(header_value, body_value) when is_binary(body_value),
      do: header_value == body_value

    defp value_matches?(header_value, true), do: header_value == "true"
    defp value_matches?(header_value, false), do: header_value == "false"

    defp value_matches?(header_value, body_value) when is_integer(body_value) do
      case Float.parse(header_value) do
        {parsed, ""} -> parsed == body_value * 1.0
        _ -> false
      end
    end

    # `x-mcp-header` "MUST only be applied to parameters with primitive types (integer, string,
    # boolean)", so a map, a list, a float or a null body value cannot be a mirrored parameter
    # and cannot match any header. Returning false rather than interpolating the value is also
    # what keeps an attacker-chosen JSON value out of the refusal message.
    defp value_matches?(_header_value, _body_value), do: false

    defp all_match?(values, name, body_value) do
      values != [] and
        Enum.all?(values, &value_matches?(decode_header_value(name, &1), body_value))
    end

    defp check_headers(conn, message, opts) do
      id = message["id"]

      with :ok <- check_protocol_version(conn, message, id),
           :ok <- check_method_header(conn, message, id),
           :ok <- check_name_header(conn, message, id),
           :ok <- check_param_headers(conn, message, id, opts) do
        {:ok, conn}
      else
        {:mismatch, status, payload} -> {:refused, conn, status, payload}
      end
    end

    # Notifications carry no id, and the revision says in terms that "header requirements for
    # notification POSTs are not defined by this revision". Requiring Mcp-Method on them would
    # be this transport inventing a rule and refusing conforming clients. The exemption is a
    # relaxation of a MUST, so it is pinned in both directions: a notification without the
    # header is served, and a notification WITH a lying header is still refused.
    defp check_method_header(conn, message, id) do
      cond do
        Map.has_key?(message, "id") -> check_named(conn, "mcp-method", message["method"], id)
        header_values(conn, "mcp-method") == [] -> :ok
        true -> check_named(conn, "mcp-method", message["method"], id)
      end
    end

    # "Mcp-Name | params.name or params.uri | tools/call, resources/read, prompts/get".
    # Of those, this package implements tools/call.
    defp check_name_header(conn, %{"method" => "tools/call"} = message, id) do
      check_named(conn, "mcp-name", param(message, "name"), id)
    end

    defp check_name_header(_conn, _message, _id), do: :ok

    # `x-mcp-header` marks a tool parameter to be mirrored into `Mcp-Param-{Name}`. The
    # annotation carries the NAME PORTION of the header and points at a property path -- "a
    # chain of properties keys", which the spec permits to be nested -- so the mapping is
    # schema -> header, and cannot be recovered by lowercasing a header suffix into a top-level
    # argument key. Doing that refused conforming clients whose annotation name differed from
    # the property key, or was not all-lowercase, or was nested, with no recovery available to
    # a client that was already correct.
    #
    # Headers not named by the schema are ignored: "intermediate servers that do not recognize
    # an Mcp-Param-{Name} header MUST forward it and otherwise ignore it".
    defp check_param_headers(conn, message, id, opts) do
      message
      |> mirrored_params(opts)
      |> Enum.reduce_while(:ok, fn {_key, {name, path}}, :ok ->
        header = "mcp-param-" <> String.downcase(name)
        values = header_values(conn, header)
        body_value = value_at(arguments(message), path)

        cond do
          # "Parameter value is null" / "parameter not in arguments" -> "server MUST NOT expect
          # the header".
          is_nil(body_value) and values == [] ->
            {:cont, :ok}

          is_nil(body_value) ->
            {:halt, param_error(id, name, "was sent, but the body carries no such value")}

          # "Client omits header but value is in body | non-conforming client | server MUST
          # reject the request."
          values == [] ->
            {:halt, param_error(id, name, "is required: the body carries a value to mirror")}

          all_match?(values, header, body_value) ->
            {:cont, :ok}

          true ->
            {:halt, param_error(id, name, "does not match the corresponding request body value")}
        end
      end)
    end

    # One lookup, `BeamMCP.ToolCatalog.fetch/2`, is what the core uses to decide whether a tool
    # is callable. The transport asks the same question of the same function: two lookups would
    # be two answers to "which tool does this name mean", which is the disagreement this whole
    # header mechanism exists to prevent.
    defp mirrored_params(%{"method" => "tools/call"} = message, opts) do
      with name when is_binary(name) <- param(message, "name"),
           catalog when not is_nil(catalog) <- opts.server_opts[:tool_catalog],
           {:ok, spec} <- ToolCatalog.fetch(catalog, name) do
        annotations(spec.input_schema)
      else
        _ -> %{}
      end
    end

    defp mirrored_params(_message, _opts), do: %{}

    # Keyed by the case-folded name because "x-mcp-header values MUST be case-insensitively
    # unique", and field names are case-insensitive; the original spelling is carried alongside
    # so the refusal can name the header the client was told to send.
    defp annotations(schema), do: annotations(schema, [])

    defp annotations(%{"properties" => properties}, path) when is_map(properties) do
      Enum.reduce(properties, %{}, fn {key, subschema}, acc ->
        acc =
          case is_map(subschema) and subschema["x-mcp-header"] do
            name when is_binary(name) and name != "" ->
              Map.put(acc, String.downcase(name), {name, path ++ [key]})

            _ ->
              acc
          end

        # Recursion runs through `properties` and nothing else: the chain "MUST NOT pass
        # through items, oneOf, anyOf, allOf, not, if/then/else or $ref".
        Map.merge(acc, annotations(subschema, path ++ [key]))
      end)
    end

    defp annotations(_schema, _path), do: %{}

    defp arguments(%{"params" => %{"arguments" => %{} = arguments}}), do: arguments
    defp arguments(_message), do: %{}

    defp value_at(value, []), do: value

    defp value_at(%{} = value, [key | rest]), do: value_at(Map.get(value, key), rest)

    defp value_at(_value, _path), do: nil

    defp param_error(id, name, complaint),
      do: {:mismatch, 400, header_error(id, "Mcp-Param-#{name} header #{complaint}")}

    defp check_named(conn, header_name, body_value, id) do
      values = header_values(conn, header_name)

      cond do
        values == [] ->
          {:mismatch, 400, header_error(id, "Missing #{header_name} header; it is required")}

        all_match?(values, header_name, body_value) ->
          :ok

        true ->
          {:mismatch, 400,
           header_error(
             id,
             "#{header_name} header does not match the corresponding request body value"
           )}
      end
    end

    # `params` is any JSON value once the body is an object. Reaching into a non-map raised in
    # `Access.get/3` -- the same defect as the `_meta` guard below, found by two lanes in code
    # written by the commit that added that guard.
    defp param(%{"params" => %{} = params}, key), do: params[key]
    defp param(_message, _key), do: nil

    defp check_protocol_version(conn, message, id) do
      values = header_values(conn, @protocol_header)

      case body_protocol_version(message) do
        :invalid ->
          {:mismatch, 400, header_error(id, "_meta must be a JSON object when present")}

        body_version ->
          compare_versions(values, body_version, id)
      end
    end

    # `_meta` is any JSON value once the body is an object, so a non-map one must be refused
    # rather than reached into.
    defp body_protocol_version(message) do
      case message["_meta"] do
        %{} = meta -> meta[@version_meta_key]
        nil -> nil
        _other -> :invalid
      end
    end

    defp compare_versions([], _body_version, id) do
      {:mismatch, 400,
       header_error(id, "Missing #{@protocol_header} header; it is required on every POST")}
    end

    # Two comparisons, and BOTH read every value. The second one is the only check on a body
    # that carries no `_meta`, and it was pinned by nothing: a mutant making it first-value-only
    # survived the suite that claimed one mutant per header read.
    defp compare_versions(values, body_version, id) do
      unsupported = Enum.reject(values, &(&1 == @modern_version))

      cond do
        not is_nil(body_version) and not all_match?(values, @protocol_header, body_version) ->
          {:mismatch, 400,
           header_error(id, "#{@protocol_header} header does not match the body value")}

        unsupported != [] ->
          {:mismatch, 400,
           %{
             "jsonrpc" => "2.0",
             "id" => id,
             "error" => %{
               "code" => -32_022,
               "message" => "Unsupported protocol version",
               "data" => %{
                 "supported" => [@modern_version],
                 # The values actually refused, not `List.first/1` of everything sent: with two
                 # headers the old payload could report a `requested` version that is in its own
                 # `supported` list, which reads as a server contradicting itself.
                 "requested" => unsupported
               }
             }
           }}

        true ->
          :ok
      end
    end

    # -- handing off to the unchanged core ---------------------------------------------------

    # A crash in the host's dispatch is the failure mode this package is most exposed to: the
    # host's code runs inside our request path. `rescue` alone was not enough -- a lane showed
    # `throw` and `exit` still giving a bare empty 500, and `GenServer.call` timing out EXITS,
    # which is the shape a host that calls a backend hits first. `catch` covers all three.
    #
    # The response carries NO detail. The reason reaches the logger, where the host can see it;
    # an HTTP caller -- possibly unauthenticated, since authorize/1 is the host's and may
    # permit anyone -- learns only that the request failed.
    defp dispatch(conn, message, opts) do
      do_dispatch(conn, message, opts)
    rescue
      exception ->
        # Same rule as call/2's, through the same function. This rescue is kept inside that one
        # only because it knows `message["id"]` by now and a crash before decoding does not --
        # and a second copy of the rule is how the status-swallowing regression survived being
        # fixed in the outer one.
        fault_response(conn, exception, __STACKTRACE__, message["id"])
    catch
      kind, reason ->
        Logger.error(Exception.format(kind, reason, __STACKTRACE__))
        send_json(conn, 500, error(message["id"], -32_603, "Internal error"))
    end

    defp do_dispatch(conn, %{"method" => method} = message, _opts)
         when method in @removed_in_modern do
      case message["id"] do
        nil -> send_resp(conn, 202, "")
        id -> send_json(conn, 404, error(id, -32_601, "#{@method_not_found} #{method}"))
      end
    end

    defp do_dispatch(conn, message, opts) do
      # The header is authoritative and mandatory here, so a body that omits `_meta` is still
      # a modern request. Supplying it keeps handle_message/2 unchanged: the core decides era
      # from the message, and the transport guarantees the message says so.
      meta = Map.put(message["_meta"] || %{}, @version_meta_key, @modern_version)
      message = Map.put(message, "_meta", meta)

      case Server.handle_message(Server.new(opts.server_opts), message) do
        {_state, nil} ->
          send_resp(conn, 202, "")

        {_state,
         %{"error" => %{"code" => -32_601, "message" => @method_not_found <> _}} =
             response} ->
          # An unimplemented METHOD is 404, not 200: a client's transport-fallback algorithm
          # reads the status, and answering 200 tells it the endpoint handled the request.
          #
          # Keyed on the method-not-found case, not on -32601, because the core raises that
          # same code for `Unknown tool: <name>` -- a `tools/call` naming a tool this server
          # does not have. That is a live endpoint answering a bad argument; 404 there told
          # the client the MCP endpoint itself was absent, and a conforming client responds
          # by abandoning the endpoint and falling back. One mistyped tool name would have
          # taken down the whole connection.
          #
          # The coupling to the core's wording is deliberate and pinned: a test asserts
          # `Server.handle_message/2` still prefixes this case with @method_not_found, so a
          # reword fails that test instead of silently turning every 404 back into a 200.
          send_json(conn, 404, response)

        {_state, response} ->
          send_json(conn, 200, response)
      end
    end

    defp send_json(conn, status, payload) do
      conn
      |> put_resp_content_type("application/json")
      |> send_resp(status, Jason.encode!(payload))
    end

    # Refusing an oversized body leaves the connection with an unread remainder. Closing makes
    # the refusal clean rather than leaving a socket whose next request is misframed.
    defp close_after(conn), do: put_resp_header(conn, "connection", "close")

    defp header_error(id, message) do
      %{
        "jsonrpc" => "2.0",
        "id" => id,
        "error" => %{"code" => -32_020, "message" => "Header mismatch: #{message}"}
      }
    end

    defp error(id, code, message) do
      %{"jsonrpc" => "2.0", "id" => id, "error" => %{"code" => code, "message" => message}}
    end

    defp type_of(v) when is_list(v), do: "an array"
    defp type_of(v) when is_binary(v), do: "a string"
    defp type_of(v) when is_number(v), do: "a number"
    defp type_of(nil), do: "null"
    defp type_of(_), do: "a scalar"
  end
end
