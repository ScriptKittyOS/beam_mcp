# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Transport.HTTPTest do
  @moduledoc """
  The HTTP transport, tested against the `2026-07-28` transport specification's own MUSTs.

  Each test names the requirement it pins. The spec text is archived in this slice's `logs/`
  rather than paraphrased, so a reader can check the quote against the page it came from.
  """
  use ExUnit.Case, async: true
  use Plug.Test

  alias BeamMCP.Transport.HTTP

  @modern "2026-07-28"
  @vkey "io.modelcontextprotocol/protocolVersion"
  @hdr "mcp-protocol-version"

  defmodule Catalog do
    @behaviour BeamMCP.ToolCatalog
    @impl true
    def all do
      [
        %BeamMCP.ToolSpec{
          name: :echo,
          command_class: :observe,
          mode: :read_only,
          description: "Echo."
        }
      ]
    end
  end

  defp opts(extra \\ []) do
    Keyword.merge(
      [
        tool_catalog: Catalog,
        dispatch: fn _n, a, _o -> {:ok, a} end,
        authorize: fn _conn -> :ok end,
        allowed_origins: :any
      ],
      extra
    )
    |> HTTP.init()
  end

  # Standard headers are REQUIRED, so the helper supplies them from the body unless a test
  # overrides them. A test that wants to omit or corrupt one passes it explicitly.
  defp std_headers(body) do
    base = [{@hdr, @modern}]
    base = if m = body["method"], do: base ++ [{"mcp-method", m}], else: base

    case body do
      %{"method" => "tools/call", "params" => %{"name" => name}} ->
        base ++ [{"mcp-name", name}]

      _ ->
        base
    end
  end

  defp post(body, headers \\ nil, o \\ nil) do
    conn =
      :post
      |> conn("/mcp", Jason.encode!(body))
      |> put_req_header("content-type", "application/json")

    conn =
      Enum.reduce(headers || std_headers(body), conn, fn {k, v}, c -> put_req_header(c, k, v) end)

    HTTP.call(conn, o || opts())
  end

  defp body!(conn), do: Jason.decode!(conn.resp_body)

  defp msg(method, extra \\ %{}) do
    Map.merge(
      %{"jsonrpc" => "2.0", "id" => 1, "method" => method, "_meta" => %{@vkey => @modern}},
      extra
    )
  end

  describe "the two options the package refuses to default" do
    test "init/1 raises without :authorize, naming what the host must decide" do
      assert_raise ArgumentError, ~r/requires an :authorize option, and it has no default/, fn ->
        HTTP.init(tool_catalog: Catalog, allowed_origins: :any)
      end
    end

    test "init/1 raises without :allowed_origins" do
      assert_raise ArgumentError, ~r/requires an :allowed_origins option/, fn ->
        HTTP.init(tool_catalog: Catalog, authorize: fn _ -> :ok end)
      end
    end

    test "the failure is at init, not at request time" do
      # The distinction is the whole contract: a host that forgets cannot start, rather than
      # serving unauthorised requests until someone notices.
      assert_raise ArgumentError, fn -> HTTP.init(tool_catalog: Catalog) end
    end

    test "an authorize that refuses stops the request before any message is handled" do
      me = self()

      o =
        opts(
          authorize: fn _ -> {:error, :nope} end,
          dispatch: fn n, a, _ ->
            send(me, {:dispatched, n})
            {:ok, a}
          end
        )

      conn =
        post(msg("tools/call", %{"params" => %{"name" => "echo", "arguments" => %{}}}), nil, o)

      assert conn.status == 403
      refute_receive {:dispatched, _}, 50
    end
  end

  describe "MCP-Protocol-Version — the header that makes the stdio no-era path impossible here" do
    test "a POST without the header is rejected" do
      # "Every POST request to the MCP endpoint MUST include an MCP-Protocol-Version header."
      conn = post(msg("tools/list"), [{"mcp-method", "tools/list"}])
      assert conn.status == 400
      # -32020 covers "required headers are missing/malformed", not only mismatch.
      assert body!(conn)["error"]["code"] == -32_020
      assert body!(conn)["error"]["message"] =~ "Missing mcp-protocol-version"
    end

    test "a header disagreeing with the body's _meta is a HeaderMismatch" do
      # "If the values do not match, the server MUST reject the request with 400 Bad Request
      #  and a HeaderMismatch JSON-RPC error."
      conn = post(msg("tools/list"), [{@hdr, "2025-11-25"}, {"mcp-method", "tools/list"}])
      assert conn.status == 400
      assert body!(conn)["error"]["code"] == -32_020
    end

    test "an unsupported version gets -32022 listing what is supported" do
      body = %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"}
      conn = post(body, [{@hdr, "1900-01-01"}, {"mcp-method", "tools/list"}])
      assert conn.status == 400
      assert body!(conn)["error"]["code"] == -32_022
      assert body!(conn)["error"]["data"]["supported"] == [@modern]
    end

    test "tools/call cannot reach dispatch without the header" do
      # This is SCR-255's hazard asked of HTTP: on stdio the bare call executes.
      me = self()

      o =
        opts(
          dispatch: fn n, a, _ ->
            send(me, {:dispatched, n})
            {:ok, a}
          end
        )

      body = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{"name" => "echo", "arguments" => %{}}
      }

      conn = post(body, [{"mcp-method", "tools/call"}, {"mcp-name", "echo"}], o)

      assert conn.status == 400
      refute_receive {:dispatched, _}, 50
    end
  end

  describe "Origin — MUST be validated to prevent DNS rebinding" do
    test "a disallowed Origin gets 403" do
      o = opts(allowed_origins: ["https://good.example"])

      conn =
        post(
          msg("tools/list"),
          [{@hdr, @modern}, {"mcp-method", "tools/list"}, {"origin", "https://evil.example"}],
          o
        )

      assert conn.status == 403
    end

    test "an allowed Origin passes" do
      o = opts(allowed_origins: ["https://good.example"])

      conn =
        post(
          msg("tools/list"),
          [{@hdr, @modern}, {"mcp-method", "tools/list"}, {"origin", "https://good.example"}],
          o
        )

      assert conn.status == 200
    end

    test "an absent Origin is not an invalid one" do
      # Non-browser clients send none; the spec conditions on the header being *present*.
      o = opts(allowed_origins: ["https://good.example"])
      conn = post(msg("tools/list"), [{@hdr, @modern}, {"mcp-method", "tools/list"}], o)
      assert conn.status == 200
    end
  end

  describe "malformed input answers, rather than crashing" do
    test "a non-POST is refused" do
      conn = HTTP.call(conn(:get, "/mcp"), opts())
      assert conn.status == 405
    end

    test "an empty body is a parse error, not an exception" do
      conn =
        :post
        |> conn("/mcp", "")
        |> put_req_header(@hdr, @modern)
        |> put_req_header("mcp-method", "tools/list")
        |> HTTP.call(opts())

      assert conn.status == 400
      assert body!(conn)["error"]["code"] == -32_700
    end

    test "invalid JSON is a parse error" do
      conn =
        :post
        |> conn("/mcp", "{not json")
        |> put_req_header(@hdr, @modern)
        |> put_req_header("mcp-method", "tools/list")
        |> HTTP.call(opts())

      assert conn.status == 400
      assert body!(conn)["error"]["code"] == -32_700
    end

    test "a JSON array is refused: batching is in neither supported revision" do
      conn =
        :post
        |> conn("/mcp", "[]")
        |> put_req_header(@hdr, @modern)
        |> put_req_header("mcp-method", "tools/list")
        |> HTTP.call(opts())

      assert conn.status == 400
    end
  end

  describe "a crash in the host's dispatch" do
    test "answers with a JSON-RPC internal error, not an empty 500" do
      # Measured before this was handled: a raising dispatch gave HTTP 500 with an EMPTY
      # body. The listener survived and the next request succeeded, so it was never a
      # stability problem -- it was a protocol one.
      o = opts(dispatch: fn _n, _a, _o -> raise "host dispatch exploded" end)

      conn =
        post(msg("tools/call", %{"params" => %{"name" => "echo", "arguments" => %{}}}), nil, o)

      assert conn.status == 500
      assert body!(conn)["error"]["code"] == -32_603
    end

    test "and leaks nothing about the host to the caller" do
      # The exception still reaches the logger, where the host can see it. An HTTP caller --
      # possibly unauthenticated, since authorize/1 is the host's and may permit anyone --
      # learns only that the request failed.
      o = opts(dispatch: fn _n, _a, _o -> raise "SECRET internal detail" end)

      conn =
        post(msg("tools/call", %{"params" => %{"name" => "echo", "arguments" => %{}}}), nil, o)

      refute conn.resp_body =~ "SECRET"
      refute conn.resp_body =~ "exploded"
      assert body!(conn)["error"]["message"] == "Internal error"
    end
  end

  describe "the standard request headers the specification requires" do
    test "Mcp-Method is required" do
      conn = post(msg("tools/list"), [{@hdr, @modern}])
      assert conn.status == 400
      assert body!(conn)["error"]["code"] == -32_020
    end

    test "an Mcp-Method disagreeing with the body is refused before dispatch" do
      # The spec names this exact vulnerability: "a load balancer routing on the header value
      # while the MCP server executes based on the body value". A lane sent
      # `Mcp-Method: tools/list` with a `tools/call` body and got 200 with dispatch reached.
      me = self()

      o =
        opts(
          dispatch: fn n, a, _ ->
            send(me, {:dispatched, n})
            {:ok, a}
          end
        )

      body = msg("tools/call", %{"params" => %{"name" => "echo", "arguments" => %{}}})

      conn =
        post(body, [{@hdr, @modern}, {"mcp-method", "tools/list"}, {"mcp-name", "echo"}], o)

      assert conn.status == 400
      assert body!(conn)["error"]["code"] == -32_020
      refute_receive {:dispatched, _}, 50
    end

    test "Mcp-Name is required on tools/call and must match params.name" do
      body = msg("tools/call", %{"params" => %{"name" => "echo", "arguments" => %{}}})

      missing = post(body, [{@hdr, @modern}, {"mcp-method", "tools/call"}])
      assert missing.status == 400

      wrong =
        post(body, [{@hdr, @modern}, {"mcp-method", "tools/call"}, {"mcp-name", "not_echo"}])

      assert wrong.status == 400
      assert body!(wrong)["error"]["code"] == -32_020
    end

    test "Mcp-Name is not required on methods that carry no name" do
      assert post(msg("tools/list")).status == 200
    end
  end

  describe "an unimplemented method" do
    test "is 404, not 200" do
      # A client's transport-fallback algorithm reads the status; 200 tells it the endpoint
      # handled the request.
      conn = post(msg("nosuch/method"))
      assert conn.status == 404
      assert body!(conn)["error"]["code"] == -32_601
    end
  end

  describe "a non-map _meta" do
    test "is refused rather than crashing outside the rescue" do
      # `_meta` is any JSON value once the body is an object. `get_in/2` on a string raised
      # FunctionClauseError in Access.get/3, outside the rescue, producing the bare empty 500
      # this module exists to avoid -- one JSON scalar away from the crash path a test covers.
      for meta <- ["x", 7, [1, 2], true] do
        body = %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list", "_meta" => meta}
        conn = post(body, [{@hdr, @modern}, {"mcp-method", "tools/list"}])

        assert conn.status == 400, "a _meta of #{inspect(meta)} should be refused, not crash"
        assert body!(conn)["error"]["code"] == -32_020
      end
    end
  end

  describe "the host's dispatch failing in ways rescue alone does not catch" do
    test "throw and exit are answered, not left as an empty 500" do
      # `rescue` catches raises only. A GenServer.call timeout EXITS, which is the shape a
      # host calling a backend hits first, and a lane measured both giving HTTP 500 with no
      # body at all -- verbatim what the changelog claimed had been eliminated.
      for dispatch <- [
            fn _n, _a, _o -> throw(:thrown_secret) end,
            fn _n, _a, _o -> exit(:kaboom_secret) end
          ] do
        o = opts(dispatch: dispatch)

        conn =
          post(msg("tools/call", %{"params" => %{"name" => "echo", "arguments" => %{}}}), nil, o)

        assert conn.status == 500
        assert body!(conn)["error"]["code"] == -32_603
        refute conn.resp_body =~ "secret"
        refute conn.resp_body =~ "thrown"
      end
    end
  end

  describe "authorization refusal tells the caller nothing about the host" do
    test "a structured refusal reason does not reach the response" do
      # A lane recovered a planted bearer token and database URL from the 403 body, because
      # the reason was interpolated with inspect/1 -- on the one branch that is by definition
      # unauthenticated, and 130 lines from a moduledoc saying the package never does this.
      o =
        opts(
          authorize: fn _ ->
            {:error, %{expected_bearer: "s3cr3t-token", db: "postgres://u:pw@10.0.0.5/prod"}}
          end
        )

      conn = post(msg("tools/list"), nil, o)

      assert conn.status == 403
      refute conn.resp_body =~ "s3cr3t"
      refute conn.resp_body =~ "postgres"
      refute conn.resp_body =~ "expected_bearer"
      assert body!(conn)["error"]["message"] == "Forbidden"
    end

    test "an authorize returning neither :ok nor {:error, _} fails closed" do
      me = self()

      o =
        opts(
          authorize: fn _ -> false end,
          dispatch: fn n, a, _ ->
            send(me, {:dispatched, n})
            {:ok, a}
          end
        )

      conn = post(msg("tools/list"), nil, o)

      assert conn.status == 403
      refute_receive {:dispatched, _}, 50
    end
  end

  describe "the body cap" do
    test "a body over the cap is refused and the connection closed" do
      big = String.duplicate("x", 1_100_000)

      conn =
        :post
        |> conn(
          "/mcp",
          Jason.encode!(%{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list", "pad" => big})
        )
        |> put_req_header(@hdr, @modern)
        |> put_req_header("mcp-method", "tools/list")
        |> HTTP.call(opts())

      assert conn.status == 413
      # Closing matters: a refusal that leaves an unread body misframes the next request on
      # a keep-alive connection.
      assert get_resp_header(conn, "connection") == ["close"]
    end

    test "a body under the cap is served" do
      pad = String.duplicate("x", 1000)
      body = Map.put(msg("tools/list"), "pad", pad)
      assert post(body).status == 200
    end
  end

  describe "the core is unchanged and reachable" do
    test "tools/list carries the fields 2026-07-28 requires" do
      conn = post(msg("tools/list"))
      result = body!(conn)["result"]

      assert result["ttlMs"] == 0
      assert result["cacheScope"] == "private"
      assert result["resultType"] == "complete"
    end

    test "the host chooses the cacheable values, and the default is not permissive" do
      o = opts(tools_ttl_ms: 60_000, tools_cache_scope: "public")
      result = post(msg("tools/list"), nil, o) |> body!() |> Map.fetch!("result")

      assert result["ttlMs"] == 60_000
      assert result["cacheScope"] == "public"
    end

    test "a notification gets 202 and no body" do
      conn =
        post(%{
          "jsonrpc" => "2.0",
          "method" => "notifications/initialized",
          "_meta" => %{@vkey => @modern}
        })

      assert conn.status == 202
      assert conn.resp_body == ""
    end

    test "tools/call reaches dispatch when everything is in order" do
      me = self()

      o =
        opts(
          dispatch: fn n, a, _ ->
            send(me, {:dispatched, n})
            {:ok, a}
          end
        )

      conn =
        post(msg("tools/call", %{"params" => %{"name" => "echo", "arguments" => %{}}}), nil, o)

      assert conn.status == 200
      assert_receive {:dispatched, :echo}
    end
  end

  # Plug.Test's put_req_header REPLACES, so duplicates have to be built directly. Every test
  # below sends two values for one header: the first satisfies the check, the second does not.
  # That is the attacker's shape -- a hop in front routes on one value, this server executes on
  # the other -- and it is the shape the spec's header-validation MUST exists to stop.
  defp post_dup(body, headers, o \\ nil) do
    conn =
      :post
      |> conn("/mcp", Jason.encode!(body))
      |> put_req_header("content-type", "application/json")

    conn = %{conn | req_headers: conn.req_headers ++ headers}
    HTTP.call(conn, o || opts())
  end

  describe "every header read validates every value, not the first" do
    # One test per header the module reads. The set is derived, not listed: `header_values/2`
    # is the only `get_req_header` call site, and the `mcp-param-` sweep is the only other read
    # of `conn.req_headers`. Each of these dies under its own mutant; see logs/mutation.md.

    test "Origin — a second, disallowed Origin is not ignored" do
      o = opts(allowed_origins: ["https://ok.example"])
      body = msg("tools/list")

      assert post_dup(
               body,
               std_headers(body) ++
                 [{"origin", "https://ok.example"}, {"origin", "https://evil.example"}],
               o
             ).status == 403
    end

    test "MCP-Protocol-Version — a second, unsupported version is not ignored" do
      body = msg("tools/list")

      conn =
        post_dup(body, [{@hdr, @modern}, {@hdr, "1999-01-01"}, {"mcp-method", "tools/list"}])

      assert conn.status == 400
    end

    test "Mcp-Method — a second, disagreeing method is not ignored" do
      me = self()
      o = opts(dispatch: fn n, a, _ -> send(me, {:dispatched, n}) && {:ok, a} end)
      body = msg("tools/list")

      conn =
        post_dup(
          body,
          [{@hdr, @modern}, {"mcp-method", "tools/list"}, {"mcp-method", "tools/call"}],
          o
        )

      assert conn.status == 400
      assert body!(conn)["error"]["code"] == -32_020
      refute_receive {:dispatched, _}, 50
    end

    test "Mcp-Name — a second, disagreeing name is not ignored" do
      body = msg("tools/call", %{"params" => %{"name" => "echo", "arguments" => %{}}})

      conn =
        post_dup(body, [
          {@hdr, @modern},
          {"mcp-method", "tools/call"},
          {"mcp-name", "echo"},
          {"mcp-name", "rm_rf"}
        ])

      assert conn.status == 400
      assert body!(conn)["error"]["code"] == -32_020
    end

    test "Mcp-Param-{Name} — a second, disagreeing value is not ignored" do
      body =
        msg("tools/call", %{
          "params" => %{"name" => "echo", "arguments" => %{"region" => "eu-west1"}}
        })

      conn =
        post_dup(body, [
          {@hdr, @modern},
          {"mcp-method", "tools/call"},
          {"mcp-name", "echo"},
          {"mcp-param-region", "eu-west1"},
          {"mcp-param-region", "us-west1"}
        ])

      assert conn.status == 400
      assert body!(conn)["error"]["code"] == -32_020
    end
  end

  describe "Mcp-Param-{Name}, which tool_definition/1 advertises via x-mcp-header" do
    defp call_body(args) do
      msg("tools/call", %{"params" => %{"name" => "echo", "arguments" => args}})
    end

    defp call_headers(extra) do
      [{@hdr, @modern}, {"mcp-method", "tools/call"}, {"mcp-name", "echo"}] ++ extra
    end

    test "a mirrored parameter that matches the body is accepted" do
      body = call_body(%{"region" => "eu-west1"})
      assert post(body, call_headers([{"mcp-param-region", "eu-west1"}])).status == 200
    end

    test "a mirrored parameter that disagrees with the body is refused before dispatch" do
      # A schema opting a parameter into `x-mcp-header` is the host telling clients the header
      # is authoritative. Advertising that and then not comparing it is worse than never
      # advertising it: a client that trusts the advertisement gets silent divergence between
      # the value it routed on and the value that ran.
      me = self()
      o = opts(dispatch: fn n, a, _ -> send(me, {:dispatched, n, a}) && {:ok, a} end)
      body = call_body(%{"region" => "eu-west1"})

      conn = post(body, call_headers([{"mcp-param-region", "us-west1"}]), o)

      assert conn.status == 400
      assert body!(conn)["error"]["code"] == -32_020
      refute_receive {:dispatched, _, _}, 50
    end

    test "a mirrored parameter naming an argument the body does not carry is refused" do
      body = call_body(%{})
      assert post(body, call_headers([{"mcp-param-region", "us-west1"}])).status == 400
    end
  end

  describe "encoded header values" do
    test "an RFC-2047-style Base64 Mcp-Name is decoded before comparison" do
      # "Servers MUST decode an encoded Mcp-Name or Mcp-Param-{Name} value before comparing it
      # to the corresponding request body value during Server Validation." Tool names are only
      # SHOULD-constrained to header-safe characters, so a conforming client calling a
      # non-ASCII tool name has no other way to satisfy the comparison, and the spec's advised
      # recovery -- re-read tools/list and retry -- cannot help a client that was already right.
      body = call_body(%{})
      encoded = "=?base64?" <> Base.encode64("echo") <> "?="

      assert post(body, [{@hdr, @modern}, {"mcp-method", "tools/call"}, {"mcp-name", encoded}]).status ==
               200
    end

    test "a Base64 value decoding to the wrong name is still refused" do
      body = call_body(%{})
      encoded = "=?base64?" <> Base.encode64("not_echo") <> "?="

      assert post(body, [{@hdr, @modern}, {"mcp-method", "tools/call"}, {"mcp-name", encoded}]).status ==
               400
    end

    test "a malformed Base64 sentinel is compared literally, not crashed on" do
      body = call_body(%{})

      assert post(body, [
               {@hdr, @modern},
               {"mcp-method", "tools/call"},
               {"mcp-name", "=?base64?!!!not-base64!!!?="}
             ]).status == 400
    end
  end

  describe "404 is the method-not-found case, not the -32601 code" do
    test "an unknown tool is 200 with a JSON-RPC error, not 404" do
      # The core answers -32601 for both `Method not found:` and `Unknown tool:`. Keying 404 on
      # the code sent 404 for a live endpoint answering a bad argument, and a conforming client
      # reads that as "no MCP endpoint here" and abandons the connection. One mistyped tool
      # name took down the session.
      body = call_body(%{}) |> put_in(["params", "name"], "nosuch_tool")

      conn =
        post(body, [{@hdr, @modern}, {"mcp-method", "tools/call"}, {"mcp-name", "nosuch_tool"}])

      assert conn.status == 200
      assert body!(conn)["error"]["code"] == -32_601
      assert body!(conn)["error"]["message"] =~ "Unknown tool"
    end

    test "an unimplemented method is still 404" do
      assert post(msg("nosuch/method")).status == 404
    end

    test "the core's wording that 404 keys on is pinned here" do
      # The transport matches the core's `Method not found:` prefix. That coupling is real, so
      # it is asserted: a reword fails this test instead of silently turning every 404 into a
      # 200 with no test noticing.
      state = BeamMCP.Server.new(tool_catalog: Catalog, dispatch: fn _, a, _ -> {:ok, a} end)

      {_, unimplemented} =
        BeamMCP.Server.handle_message(state, %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "nosuch/method"
        })

      assert unimplemented["error"]["message"] =~ ~r/^Method not found:/

      {_, unknown_tool} =
        BeamMCP.Server.handle_message(state, %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "tools/call",
          "params" => %{"name" => "nosuch_tool", "arguments" => %{}}
        })

      refute unknown_tool["error"]["message"] =~ ~r/^Method not found:/
    end
  end

  describe "body values that are not strings" do
    test "a non-scalar params.name is refused, not interpolated into a message" do
      # Header comparison interpolated the body value into the refusal text, so a JSON array
      # raised Protocol.UndefinedError for String.Chars -- a crash on the refusal path. It is
      # inside the rescue now, but a refusal must not need the rescue to be a refusal.
      body = msg("tools/call", %{"params" => %{"name" => ["echo"], "arguments" => %{}}})

      conn = post(body, [{@hdr, @modern}, {"mcp-method", "tools/call"}, {"mcp-name", "echo"}])

      assert conn.status == 400
      assert body!(conn)["error"]["code"] == -32_020

      # And the refusal does not echo the body value back. Interpolating it was how the crash
      # got in; the value is also attacker-chosen text being reflected to an unauthenticated
      # caller, so the message names the header and says nothing about what was in it.
      refute body!(conn)["error"]["message"] =~ "echo"
    end

    test "a non-map params is refused, not reached into" do
      body = msg("tools/call", %{"params" => "not-a-map"})

      conn = post(body, [{@hdr, @modern}, {"mcp-method", "tools/call"}, {"mcp-name", "echo"}])

      assert conn.status == 400
    end
  end

  describe ":tool_catalog is checked for the behaviour, not for truthiness" do
    test "a value that is not a module exporting all/0 raises at init, not at the first request" do
      for bad <- [true, "MyApp.Catalog", Enum, :not_a_module] do
        assert_raise ArgumentError, ~r/BeamMCP.ToolCatalog behaviour/, fn ->
          HTTP.init(
            tool_catalog: bad,
            dispatch: fn _, a, _ -> {:ok, a} end,
            authorize: fn _ -> :ok end,
            allowed_origins: :any
          )
        end
      end
    end
  end

  describe "the whole request path is inside the rescue, not just dispatch" do
    test "a host authorize/1 that raises, throws or exits is answered, not left as a bare 500" do
      # authorize/1 is the one callback reachable before authentication, and it is the one most
      # likely to touch a session store or a database -- so it is the one most likely to time
      # out. It ran outside the rescue: raise, throw and exit each produced a bodyless 500 with
      # a stacktrace and no JSON-RPC answer at all.
      crashes = [
        fn _conn -> raise "authorize exploded: bearer s3cr3t-token" end,
        fn _conn -> throw(:authorize_threw) end,
        fn _conn -> exit(:authorize_exited) end
      ]

      for crash <- crashes do
        conn = post(msg("tools/list"), nil, opts(authorize: crash))

        assert conn.status == 500
        assert body!(conn)["error"]["code"] == -32_603
        assert body!(conn)["error"]["message"] == "Internal error"
        refute conn.resp_body =~ "s3cr3t-token"
      end
    end

    test "a refusal built from a hostile header is answered, not dropped" do
      # A latin-1 byte in Mcp-Name produced no response at all: the refusal path itself raised,
      # outside every rescue, and the connection was left with nothing written on it.
      body = msg("tools/call", %{"params" => %{"name" => "echo", "arguments" => %{}}})

      conn =
        post(body, [{@hdr, @modern}, {"mcp-method", "tools/call"}, {"mcp-name", <<0xFF, 0xFE>>}])

      assert conn.state == :sent
      assert conn.status == 400
      assert body!(conn)["error"]["code"] == -32_020
    end
  end
end
