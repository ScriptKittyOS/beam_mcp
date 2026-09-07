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

    | requirement | behaviour |
    |---|---|
    | `MCP-Protocol-Version` on every POST | missing -> `400`, `-32020` |
    | header must match the body's `_meta` | mismatch -> `400`, `-32020` |
    | `Mcp-Method` on every request | missing or mismatched -> `400`, `-32020` |
    | `Mcp-Name` on `tools/call` | missing or mismatched -> `400`, `-32020` |
    | unsupported version | `400`, `-32022` |
    | invalid `Origin` | `403` |
    | non-POST | `405` |
    | unknown method | `404`, `-32601` |

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

    @modern_version "2026-07-28"
    @version_meta_key "io.modelcontextprotocol/protocolVersion"
    @protocol_header "mcp-protocol-version"

    # 1 MiB of decoded body. Without a cap, a request body is an unbounded allocation an
    # unauthenticated caller controls.
    @max_body_bytes 1_048_576
    @method_not_found "Method not found:"

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
      unless is_atom(catalog) and catalog != nil and Code.ensure_loaded?(catalog) and
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
        Logger.error(Exception.format(:error, exception, __STACKTRACE__))
        crash_response(conn)
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
           {:ok, conn} <- check_headers(conn, message) do
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
    # "When rejecting a request due to header validation failure, servers MUST return HTTP
    # status 400 Bad Request and MUST include a JSON-RPC error response using -32020
    # [HeaderMismatch] ... or required headers are missing/malformed."
    #
    # EVERY header read in this module goes through `header_values/2` and is compared with
    # `all_match?/2`. That is deliberate and it is the second attempt: the first version fixed
    # multi-value validation for `Origin` and then wrote three new single-value reads in the
    # same commit, so a duplicate `Mcp-Method` -- good value first, hostile value second --
    # returned 200 and ran the body's method. An attacker controls both values, so single-value
    # validation lets them satisfy this server while showing the hop in front something else,
    # which is exactly the smuggling the spec text above exists to stop.
    #
    # The set is derived rather than listed: `grep -n 'get_req_header' lib/beam_mcp/transport/http.ex`
    # returns only `header_values/2` and the `mcp-param-` sweep. A fourth header added later
    # inherits the behaviour instead of needing a fifth finding.
    defp header_values(conn, name), do: get_req_header(conn, name)

    # "Servers MUST decode an encoded Mcp-Name or Mcp-Param-{Name} value before comparing it to
    # the corresponding request body value during Server Validation." Tool names are only
    # SHOULD-constrained to header-safe characters and this package constrains them not at all,
    # so a conforming client calling a tool named `:"café_search"` MUST use this form -- and
    # before this, could never satisfy the comparison, with the spec's advised recovery
    # (re-read tools/list and retry) unable to help because the client was already correct.
    defp decode_header_value("=?base64?" <> rest) do
      case String.split(rest, "?=", parts: 2) do
        [encoded, ""] ->
          case Base.decode64(encoded) do
            {:ok, decoded} -> decoded
            :error -> "=?base64?" <> rest
          end

        _ ->
          "=?base64?" <> rest
      end
    end

    defp decode_header_value(value), do: value

    defp all_match?(values, expected) do
      values != [] and Enum.all?(values, &(decode_header_value(&1) == expected))
    end

    defp check_headers(conn, message) do
      id = message["id"]

      with :ok <- check_protocol_version(conn, message, id),
           :ok <- check_method_header(conn, message, id),
           :ok <- check_name_header(conn, message, id),
           :ok <- check_param_headers(conn, message, id) do
        {:ok, conn}
      else
        {:mismatch, status, payload} -> {:refused, conn, status, payload}
      end
    end

    # Notifications carry no id, and the revision says in terms that "header requirements for
    # notification POSTs are not defined by this revision". Requiring Mcp-Method on them would
    # be this transport inventing a rule and refusing conforming clients.
    defp check_method_header(conn, message, id) do
      if Map.has_key?(message, "id"),
        do: check_named(conn, "mcp-method", message["method"], id),
        else: :ok
    end

    # "Mcp-Name | params.name or params.uri | tools/call, resources/read, prompts/get".
    # Of those, this package implements tools/call.
    defp check_name_header(conn, %{"method" => "tools/call"} = message, id) do
      check_named(conn, "mcp-name", param(message, "name"), id)
    end

    defp check_name_header(_conn, _message, _id), do: :ok

    # Mcp-Param-{Name} mirrors a tool argument into a header, opted into by a tool's schema via
    # `x-mcp-header`. `tool_definition/1` passes that annotation through to `tools/list`
    # verbatim, so a host can turn the feature on and conforming clients then MUST mirror the
    # parameters -- and a transport that advertises the contract and does not enforce it is
    # worse than one that never advertised it, because a client trusting the advertisement gets
    # silent divergence between what it sent and what ran. A lane measured
    # `Mcp-Param-Region: us-west1` against a body saying `eu-west1` returning 200 with dispatch.
    #
    # The population is derived from the request rather than from the schema: every
    # `mcp-param-*` header present must match the argument of that name.
    defp check_param_headers(conn, message, id) do
      conn.req_headers
      |> Enum.filter(fn {name, _} -> String.starts_with?(name, "mcp-param-") end)
      |> Enum.map(fn {name, _} -> name end)
      |> Enum.uniq()
      |> Enum.reduce_while(:ok, fn header, :ok ->
        arg_name = String.replace_prefix(header, "mcp-param-", "")

        case check_named(conn, header, argument(message, arg_name), id) do
          :ok -> {:cont, :ok}
          mismatch -> {:halt, mismatch}
        end
      end)
    end

    defp check_named(conn, header_name, body_value, id) do
      values = header_values(conn, header_name)
      expected = to_comparable(body_value)

      cond do
        values == [] ->
          {:mismatch, 400, header_error(id, "Missing #{header_name} header; it is required")}

        all_match?(values, expected) ->
          :ok

        true ->
          {:mismatch, 400,
           header_error(
             id,
             "#{header_name} header does not match the corresponding request body value"
           )}
      end
    end

    # Body values are attacker-chosen JSON and need not be strings. Interpolating one into a
    # message raised `Protocol.UndefinedError` for String.Chars before this existed -- another
    # crash on the refusal path, which is now also inside the rescue, but a refusal should not
    # depend on the rescue to be a refusal.
    defp to_comparable(value) when is_binary(value), do: value
    defp to_comparable(value) when is_number(value), do: to_string(value)
    defp to_comparable(value) when is_boolean(value), do: to_string(value)
    defp to_comparable(nil), do: nil
    defp to_comparable(_other), do: :unmatchable

    # `params` is any JSON value once the body is an object. Reaching into a non-map raised in
    # `Access.get/3` -- the same defect as the `_meta` guard three functions above, found by two
    # lanes in code written by the commit that added that guard.
    defp param(%{"params" => %{} = params}, key), do: params[key]
    defp param(_message, _key), do: nil

    defp argument(%{"params" => %{"arguments" => %{} = args}}, key), do: args[key]
    defp argument(message, key), do: param(message, key)

    defp check_protocol_version(conn, message, id) do
      values = header_values(conn, @protocol_header)

      case body_protocol_version(message) do
        :invalid ->
          {:mismatch, 400, header_error(id, "_meta must be a JSON object when present")}

        body_version ->
          compare_versions(values, to_comparable(body_version), id)
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

    defp compare_versions(values, body_version, id) do
      cond do
        not is_nil(body_version) and not all_match?(values, body_version) ->
          {:mismatch, 400,
           header_error(id, "#{@protocol_header} header does not match the body value")}

        not Enum.all?(values, &(&1 == @modern_version)) ->
          {:mismatch, 400,
           %{
             "jsonrpc" => "2.0",
             "id" => id,
             "error" => %{
               "code" => -32_022,
               "message" => "Unsupported protocol version",
               "data" => %{"supported" => [@modern_version], "requested" => List.first(values)}
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
        Logger.error(Exception.format(:error, exception, __STACKTRACE__))
        send_json(conn, 500, error(message["id"], -32_603, "Internal error"))
    catch
      kind, reason ->
        Logger.error(Exception.format(kind, reason, __STACKTRACE__))
        send_json(conn, 500, error(message["id"], -32_603, "Internal error"))
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
