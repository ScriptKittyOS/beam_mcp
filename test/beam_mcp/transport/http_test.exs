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
          description: "Echo.",
          # The mirrored-parameter population comes from HERE, not from the caller's headers.
          # Four shapes on purpose, because the first implementation derived the argument key by
          # lowercasing the header suffix and every one of these breaks that:
          #   region     -> "Region"      name portion differs from the key only in case
          #   max_rows   -> "maxRows"     name portion is not the key at all
          #   nested     -> "Nested"      the value lives at a nested properties path
          #   plain      -> (none)        not annotated: no header is expected or accepted
          input_schema: %{
            "type" => "object",
            "properties" => %{
              "region" => %{"type" => "string", "x-mcp-header" => "Region"},
              "max_rows" => %{"type" => "integer", "x-mcp-header" => "maxRows"},
              "plain" => %{"type" => "string"},
              "outer" => %{
                "type" => "object",
                "properties" => %{
                  "inner" => %{"type" => "string", "x-mcp-header" => "Nested"}
                }
              }
            },
            "additionalProperties" => true
          }
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

  describe "the Base64 sentinel is decoded for the headers that permit it, and no others" do
    test "Mcp-Method is NOT decoded" do
      # "For headers that permit the Base64 sentinel encoding (Mcp-Name and Mcp-Param-{Name}),
      # servers MUST decode encoded values." Mcp-Method is not in that set. Decoding it let
      # `Mcp-Method: =?base64?dG9vbHMvY2FsbA==?=` satisfy this server while a gateway filtering
      # on Mcp-Method saw an opaque token -- the fix for one MUST reopening the hole the other
      # MUST closes.
      body = call_body(%{})
      encoded = "=?base64?" <> Base.encode64("tools/call") <> "?="

      conn = post(body, [{@hdr, @modern}, {"mcp-method", encoded}, {"mcp-name", "echo"}])

      assert conn.status == 400
      assert body!(conn)["error"]["code"] == -32_020
    end

    test "MCP-Protocol-Version is NOT decoded" do
      encoded = "=?base64?" <> Base.encode64(@modern) <> "?="
      body = msg("tools/list")

      assert post(body, [{@hdr, encoded}, {"mcp-method", "tools/list"}]).status == 400
    end

    test "a non-canonical Base64 encoding is not accepted as a second spelling" do
      # Base.decode64/1 accepts non-canonical trailing bits, so ZWNobw==, ZWNobx==, ZWNoby==
      # and ZWNobz== all decode to "echo". Four spellings of one value means a hop comparing
      # bytes and a server comparing decoded values disagree, which is the whole vulnerability.
      body = call_body(%{})

      for variant <- ["ZWNobx==", "ZWNoby==", "ZWNobz=="] do
        conn =
          post(body, [
            {@hdr, @modern},
            {"mcp-method", "tools/call"},
            {"mcp-name", "=?base64?" <> variant <> "?="}
          ])

        assert conn.status == 400, "#{variant} was accepted as a spelling of echo"
      end

      canonical = "=?base64?" <> Base.encode64("echo") <> "?="

      assert post(body, [{@hdr, @modern}, {"mcp-method", "tools/call"}, {"mcp-name", canonical}]).status ==
               200
    end
  end

  describe "the mirrored-parameter population comes from the tool's schema" do
    test "a header the schema requires and the client omits is refused" do
      # The spec's fourth server-behaviour row: "Client omits header but value is in body |
      # non-conforming client | Server MUST reject the request." Deriving the population from
      # the caller's own headers made this unenforceable by construction -- the caller decided
      # what would be checked -- and it returned 200 with dispatch.
      me = self()
      o = opts(dispatch: fn n, a, _ -> send(me, {:dispatched, n, a}) && {:ok, a} end)
      body = call_body(%{"region" => "eu-west1"})

      conn = post(body, call_headers([]), o)

      assert conn.status == 400
      assert body!(conn)["error"]["code"] == -32_020
      refute_receive {:dispatched, _, _}, 50
    end

    test "the annotation's name portion is the header name, not the lowercased argument key" do
      # `max_rows` is annotated "maxRows". Deriving the argument key by lowercasing the header
      # suffix looked for an argument called `maxrows`, found nothing, and refused a conforming
      # client with no recovery available to it -- it was already correct.
      body = call_body(%{"max_rows" => 10})

      assert post(body, call_headers([{"mcp-param-maxrows", "10"}])).status == 200
    end

    test "an annotated property at a nested path is read at that path" do
      # "Nested object properties are permitted as long as every step in the chain is a
      # properties key."
      body = call_body(%{"outer" => %{"inner" => "deep"}})

      assert post(body, call_headers([{"mcp-param-nested", "deep"}])).status == 200
      assert post(body, call_headers([{"mcp-param-nested", "shallow"}])).status == 400
    end

    test "a header the schema does not name is ignored, not refused" do
      # "Intermediate servers that do not recognize an Mcp-Param-{Name} header MUST forward it
      # and otherwise ignore it." `plain` is a real argument that is NOT annotated, so no
      # header is expected for it and an unrecognized one is not this server's business.
      body = call_body(%{"plain" => "value"})

      assert post(body, call_headers([{"mcp-param-plain", "anything-at-all"}])).status == 200
      assert post(body, call_headers([{"mcp-param-unheard-of", "x"}])).status == 200
    end

    test "an argument absent from the body expects no header, and refuses one" do
      body = call_body(%{})

      assert post(body, call_headers([])).status == 200
      assert post(body, call_headers([{"mcp-param-region", "eu-west1"}])).status == 400
    end

    test "several mirrored parameters are all checked, not just the first" do
      # The loop over the annotations was pinned by nothing: every test sent exactly one header.
      body = call_body(%{"region" => "eu-west1", "max_rows" => 10})

      assert post(
               body,
               call_headers([{"mcp-param-region", "eu-west1"}, {"mcp-param-maxrows", "10"}])
             ).status == 200

      assert post(
               body,
               call_headers([{"mcp-param-region", "eu-west1"}, {"mcp-param-maxrows", "99"}])
             ).status == 400

      assert post(
               body,
               call_headers([{"mcp-param-region", "us-west1"}, {"mcp-param-maxrows", "10"}])
             ).status == 400
    end

    test "a mirrored parameter is read from arguments, never from params" do
      # `argument/2` fell back to `params`, so Mcp-Param-Region could be satisfied by a
      # `params.region` that the tool never receives: the header agreed with something, and the
      # something was not what ran.
      body =
        msg("tools/call", %{
          "params" => %{"name" => "echo", "arguments" => %{}, "region" => "eu-west1"}
        })

      assert post(body, call_headers([{"mcp-param-region", "eu-west1"}])).status == 400
    end

    test "an integer parameter is compared numerically, not as a string" do
      # "Servers SHOULD compare the header value and the body value numerically rather than as
      # strings (e.g. 42.0 and 42 are considered equal)."
      body = call_body(%{"max_rows" => 42})

      assert post(body, call_headers([{"mcp-param-maxrows", "42"}])).status == 200
      assert post(body, call_headers([{"mcp-param-maxrows", "42.0"}])).status == 200
      assert post(body, call_headers([{"mcp-param-maxrows", "43"}])).status == 400
      assert post(body, call_headers([{"mcp-param-maxrows", "forty-two"}])).status == 400
    end

    test "a refusal names the schema's header, never the caller's string" do
      body = call_body(%{"region" => "eu-west1"})
      hostile = "<script>alert(1)</script>"

      conn = post(body, call_headers([{"mcp-param-region", hostile}]))

      assert conn.status == 400
      assert body!(conn)["error"]["message"] =~ "Mcp-Param-Region"
      refute conn.resp_body =~ "script"
      refute conn.resp_body =~ "eu-west1"
    end
  end

  describe "the notification exemption is a relaxation, so it is pinned both ways" do
    test "a notification without Mcp-Method is served" do
      notification = %{"jsonrpc" => "2.0", "method" => "exit", "_meta" => %{@vkey => @modern}}

      assert post(notification, [{@hdr, @modern}]).status == 202
    end

    test "a notification WITH a lying Mcp-Method is still refused" do
      # The revision leaves header requirements for notification POSTs undefined, which is a
      # reason not to REQUIRE the header -- not a reason to accept one that disagrees with the
      # body. An id-less request with a lying Mcp-Method was answered 202.
      notification = %{"jsonrpc" => "2.0", "method" => "exit", "_meta" => %{@vkey => @modern}}

      conn = post(notification, [{@hdr, @modern}, {"mcp-method", "tools/call"}])

      assert conn.status == 400
      assert body!(conn)["error"]["code"] == -32_020
    end
  end

  describe "the protocol-version header has two comparisons and both read every value" do
    test "a second, unsupported version is refused on a body carrying no _meta" do
      # The mutation table claimed one mutant per header read and had one per header NAME. This
      # branch -- the only version check that runs when the body has no `_meta` -- was pinned by
      # nothing, and a first-value-only mutant survived the whole suite.
      body = %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"}

      conn =
        post_dup(body, [
          {@hdr, @modern},
          {@hdr, "1999-01-01"},
          {"mcp-method", "tools/list"}
        ])

      assert conn.status == 400
      assert body!(conn)["error"]["code"] == -32_022
    end

    test "the unsupported-version payload reports what was refused, not what was sent first" do
      # `requested` was `List.first(values)`, so with two headers the server could name a
      # version that appears in its own `supported` list -- a payload contradicting itself.
      body = %{"jsonrpc" => "2.0", "id" => 1, "method" => "tools/list"}

      conn =
        post_dup(body, [{@hdr, @modern}, {@hdr, "1999-01-01"}, {"mcp-method", "tools/list"}])

      data = body!(conn)["error"]["data"]
      assert data["requested"] == ["1999-01-01"]
      refute @modern in data["requested"]
    end
  end

  describe "an exception that carries its own HTTP status belongs to the server, not to us" do
    test "a host authorize/1's exception does not choose the HTTP status either" do
      # ROUND 5, FOUND BY TWO LANES INDEPENDENTLY. The rule was applied to dispatch/3 and the
      # comment beside it claimed "every exception, throw and exit out of the host". The
      # population was LISTED, not derived. Derived by command, host-supplied code runs at three
      # sites in the request path -- authorize/1, ToolCatalog.fetch/2 and Server.handle_message/2
      # -- and only the third was inside the rescue that was fixed.
      #
      # authorize/1 is the branch this module's own docs call possibly unauthenticated.
      o = opts(authorize: fn _conn -> raise Plug.BadRequestError end)
      body = call_body(%{}) |> Map.put("id", 91)

      conn = post(body, call_headers([]), o)

      assert conn.status == 500
      assert body!(conn)["error"]["code"] == -32_603
    end

    test "a host tool_catalog's exception does not choose the HTTP status either" do
      # The catalog raises ONCE, and that is the whole design of this test.
      #
      # The first version raised on every call, so `Server.handle_message/2`'s own lookup raised
      # too and produced the same 500/-32603 by a different route. It asserted only the status
      # and the code -- neither of which distinguishes the routes -- so a mutant swallowing the
      # catalog fault back to `%{}` in `mirrored_params/2` SURVIVED at 133 tests, 0 failures
      # while serving a lying mirrored header 200 and dispatched. An anchor that cannot move
      # under the mutation carries no information.
      #
      # Raising once separates them: header validation sees the fault, the core's later lookup
      # succeeds. So if the fault were swallowed, this request would be served rather than
      # refused -- which is exactly the mutant.
      defmodule FlakyCatalog do
        @behaviour BeamMCP.ToolCatalog
        @impl true
        def all do
          case Process.put(:flaky_called, true) do
            nil ->
              raise Plug.BadRequestError

            true ->
              [
                %BeamMCP.ToolSpec{
                  name: :echo,
                  command_class: :observe,
                  mode: :read_only,
                  description: "Echo.",
                  input_schema: %{
                    "type" => "object",
                    "properties" => %{
                      "max_rows" => %{"type" => "integer", "x-mcp-header" => "maxRows"}
                    },
                    "additionalProperties" => true
                  }
                }
              ]
          end
        end
      end

      Process.delete(:flaky_called)
      o = opts(tool_catalog: FlakyCatalog)

      # A header that LIES about the body value: 99 against a body of 42. If mirroring is
      # silently disabled by the swallowed fault, this is dispatched.
      body = call_body(%{"max_rows" => 42}) |> Map.put("id", 92)
      conn = post(body, call_headers([{"mcp-param-maxrows", "99"}]), o)

      assert conn.status == 500
      assert body!(conn)["error"]["code"] == -32_603

      # The echoed id is what proves this came from header validation and not from the core:
      # `authorize/1` faults before the body is read and answer `id: null`, and the commit that
      # returned the fault rather than throwing it did so precisely "so the id stays available".
      assert body!(conn)["id"] == 92
    end

    test "a host tool_catalog that THROWS is answered with the id, not just rescued" do
      # host_call/1 has a `catch` as well as a `rescue`, and a mutant dropping the `catch`
      # survived the suite: the throw propagated to call/2's own catch, which answers with
      # `id: null`. Status and code were identical, so only the id moves under that mutation.
      defmodule ThrowingCatalog do
        @behaviour BeamMCP.ToolCatalog
        @impl true
        def all do
          case Process.put(:throwing_called, true) do
            nil ->
              throw(:catalog_unavailable)

            true ->
              [
                %BeamMCP.ToolSpec{
                  name: :echo,
                  command_class: :observe,
                  mode: :read_only,
                  description: "Echo.",
                  input_schema: %{
                    "type" => "object",
                    "properties" => %{
                      "max_rows" => %{"type" => "integer", "x-mcp-header" => "maxRows"}
                    },
                    "additionalProperties" => true
                  }
                }
              ]
          end
        end
      end

      Process.delete(:throwing_called)
      body = call_body(%{"max_rows" => 42}) |> Map.put("id", 93)

      conn =
        post(
          body,
          call_headers([{"mcp-param-maxrows", "99"}]),
          opts(tool_catalog: ThrowingCatalog)
        )

      assert conn.status == 500
      assert body!(conn)["error"]["code"] == -32_603
      assert body!(conn)["id"] == 93
    end

    test "a host authorize/1 returning a fault-shaped tuple is a contract violation, not a fault" do
      # The internal fault sentinel shares a value space with authorize/1's return, whose
      # contract is open. Tagged with the module and five wide so a host cannot collide with it
      # by accident; this pins that a host returning the OLD four-element shape is still handled
      # as "neither :ok nor {:error, _}" -- fail closed with 403, not read as an internal fault.
      o = opts(authorize: fn _conn -> {:host_fault, :error, %RuntimeError{message: "x"}, []} end)

      conn = post(call_body(%{}), call_headers([]), o)

      assert conn.status == 403
      assert body!(conn)["error"]["message"] == "Forbidden"
    end

    test "a fault-shaped tuple tagged with another module is not our sentinel either" do
      # The collision fix has two halves -- five elements AND the module tag -- and only the
      # width was pinned: relaxing both consumers to `{_mod, :host_fault, ...}` kept the suite
      # green. The tag is what makes the sentinel private, so it gets its own anchor.
      o =
        opts(
          authorize: fn _conn ->
            {SomeOtherModule, :host_fault, :error, %RuntimeError{message: "x"}, []}
          end
        )

      conn = post(call_body(%{}), call_headers([]), o)

      assert conn.status == 403
      assert body!(conn)["error"]["message"] == "Forbidden"
    end

    test "an exception with no status of its own, raised outside host_call/1, keeps the envelope" do
      # This drives `call/2`'s rescue and `fault_response/4`'s answer branch, which lost their
      # only cover when the assert_raise stand-in was deleted: mutants making fault_response/4
      # never re-raise AND always re-raise both survived at 133 tests, 0 failures, where both
      # were killed before. The always-re-raise mutant serves a bodyless 500 -- the exact failure
      # this module exists to avoid -- so this branch is load-bearing, not dead.
      #
      # Reached with host DATA rather than a host raise: `annotations(spec.input_schema)` sits in
      # the `with` body, outside `host_call/1`, so a catalog returning a spec-shaped map that is
      # not a ToolSpec raises KeyError there.
      defmodule BadSpecCatalog do
        @behaviour BeamMCP.ToolCatalog
        @impl true
        def all, do: [%{name: :echo}]
      end

      conn = post(call_body(%{}), call_headers([]), opts(tool_catalog: BadSpecCatalog))

      assert conn.status == 500
      # A body at all is half the point: the mutant that re-raises everything sends none.
      assert conn.resp_body != ""
      assert body!(conn)["error"]["code"] == -32_603
      assert body!(conn)["jsonrpc"] == "2.0"

      # `id: null` is what proves this went through call/2's rescue rather than
      # check_param_headers/4's fault branch, which answers with the request's id. Without it,
      # moving `annotations(spec.input_schema)` inside host_call/1 -- this module's own stated
      # discipline for host territory -- reroutes the test and disarms the mutant it exists to
      # kill, silently. Measured: that refactor plus the always-re-raise mutant is green
      # without this line.
      assert body!(conn)["id"] == nil
    end

    # DELETED, AND THE GAP IS RECORDED RATHER THAN REFILLED WITH A STAND-IN.
    #
    # A test here used to assert that a status-carrying exception is re-raised, and it raised
    # from `authorize:` to do it. Both round-5 lanes found the same thing: `authorize/1` is the
    # HOST's, so that test pinned the very defect the tests above now fix, and a green suite
    # recorded the un-fixed half as correct. Its comment said the question was "filed, not
    # settled here"; `grep -rn -i filed` returned exactly one hit, the comment itself. Nothing
    # was filed. That is a claim of evidence that was never produced, which CONVENTIONS.md names
    # as the worst member of its family, so the test is deleted rather than reworded.
    #
    # It is not replaced, because after the fix there is nothing left in this suite that can
    # reach the re-raise. `fault_response/4` is now reached only from `call/2`'s rescue, and the
    # only non-host code under it that raises a status-carrying exception is the adapter's read
    # path -- `Bandit.HTTPError` at 400 for a malformed transfer coding, `Plug.TimeoutError` at
    # 408 for a read timeout. `Plug.Test` produces neither: its `read_body/2` is a
    # `:binary.part` of an in-memory binary.
    #
    # WHAT IS AND IS NOT COVERED, measured rather than asserted -- the first version of this
    # comment named only half of what the deletion cost, and a lane measured the rest.
    #
    #   fault_response/4 ALWAYS re-raises   -> KILLED, 136 tests, 1 failure
    #     by "an exception with no status of its own ... keeps the envelope" below. That mutant
    #     serves a bodyless 500, which is the failure this module exists to avoid, and it
    #     survived for one round after the stand-in was deleted.
    #
    #   fault_response/4 NEVER re-raises    -> SURVIVES, 137 tests, 0 failures
    #     Still unpinned, and honestly so. Detecting it needs an exception with a non-500
    #     :plug_status raised by code that is NOT the host's -- which after this round's fix
    #     means the adapter's read path alone: Bandit.HTTPError at 400 for a malformed transfer
    #     coding, Plug.TimeoutError at 408 for a read timeout. Plug.Test produces neither; its
    #     read_body/2 is a :binary.part of an in-memory binary.
    #
    # So the answer branch is pinned here and the re-raise branch is not. The re-raise branch is
    # covered by lane probes against a live Bandit listener, archived in this slice's logs.
    # Closing it properly needs a Bandit-backed test. That is new work, and it is recorded in
    # the slice FINDINGS rather than described here as filed -- the last time this comment said
    # something was filed, grep found exactly one hit and it was the comment.

    test "an exception with no status of its own is still answered as -32603" do
      o = opts(dispatch: fn _, _, _ -> raise "ordinary fault" end)
      conn = post(call_body(%{}), call_headers([]), o)

      assert conn.status == 500
      assert body!(conn)["error"]["code"] == -32_603
    end

    test "a dispatch crash answers with the request's id, not nil" do
      # dispatch/3 keeps its own rescue inside call/2's precisely because it knows the id by
      # then. Nothing asserted that, so removing it would have silently downgraded every
      # dispatch-time crash to an unidentifiable error response.
      o = opts(dispatch: fn _, _, _ -> raise "ordinary fault" end)
      body = call_body(%{}) |> Map.put("id", 4242)

      conn = post(body, call_headers([]), o)

      assert body!(conn)["id"] == 4242
    end
  end

  describe "methods the modern revision removed are not reachable over HTTP" do
    test "initialize, notifications/initialized and ping are all method-not-found" do
      # The transport stamps every request as `2026-07-28`, and that revision deleted the
      # handshake. `initialize` was nevertheless served by the legacy handler and answered
      # `protocolVersion: "2025-11-25"` with HTTP 200 -- an HTTP caller could open a handshake
      # the declared revision does not have and be told a different revision's version number,
      # while the README said `initialize` was not implemented.
      for method <- ["initialize", "ping"] do
        conn = post(msg(method))

        assert conn.status == 404, "#{method} was served"
        assert body!(conn)["error"]["code"] == -32_601
        refute conn.resp_body =~ "2025-11-25"
      end
    end

    test "the notification form of the handshake is not served either" do
      notification = %{
        "jsonrpc" => "2.0",
        "method" => "notifications/initialized",
        "_meta" => %{@vkey => @modern}
      }

      conn = post(notification, [{@hdr, @modern}, {"mcp-method", "notifications/initialized"}])

      # 202, because JSON-RPC forbids answering a notification and the HTTP status is the only
      # answer available -- but it is accepted-and-discarded at the transport, never handed to
      # the core, so it cannot open a handshake the declared revision does not have.
      assert conn.status == 202
      assert conn.resp_body == ""
    end
  end

  describe "an integer body value is compared as an integer, not through a float" do
    # The spec's SHOULD -- "servers SHOULD compare the header value and the body value
    # numerically rather than as strings (e.g., `42.0` and `42` are considered equal)" -- was
    # implemented as `Float.parse(header) == body * 1.0`. Erlang integers are arbitrary
    # precision and floats are not, so that expression is neither total nor injective. Both
    # halves are pinned here, and so is the allowance that motivated the float in the first
    # place, because a fix that refuses `42.0` trades one defect for another.

    test "a body integer beyond the float range is refused, not crashed into a 500" do
      # `body * 1.0` raises ArithmeticError above ~1.8e308, which JSON expresses in 310
      # characters. Reached here through `_meta` protocolVersion, which `check_protocol_version`
      # compares before any catalog lookup -- so it needs no tool and no valid name, and the
      # module's own docs describe this path as possibly unauthenticated.
      huge = String.to_integer(String.duplicate("9", 400))

      body = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/list",
        "_meta" => %{@vkey => huge}
      }

      conn = post(body, [{@hdr, "1"}, {"mcp-method", "tools/list"}])

      assert conn.status == 400
      assert body!(conn)["error"]["code"] == -32_020
    end

    test "a header naming a different integer above 2^53 is refused" do
      # Above 2^53 the integer-to-double map is not injective: 9007199254740993 and
      # 9007199254740992 are distinct integers and one float. Comparing through `* 1.0` makes
      # `Mcp-Param-{Name}` accept a header that names a different number than the body -- which
      # is the exact disagreement the header exists to prevent.
      me = self()
      o = opts(dispatch: fn n, a, _ -> send(me, {:dispatched, n, a}) && {:ok, a} end)
      body = call_body(%{"max_rows" => 9_007_199_254_740_993})

      conn = post(body, call_headers([{"mcp-param-maxrows", "9007199254740992"}]), o)

      assert conn.status == 400
      assert body!(conn)["error"]["code"] == -32_020
      refute_receive {:dispatched, _, _}, 50
    end

    test "the spec's 42.0 and 42 allowance still holds" do
      # The reason the float path was written. A fix that compares strings, or that refuses any
      # header carrying a decimal point, regresses this -- so it is pinned alongside the two
      # defects rather than left to be rediscovered.
      body = call_body(%{"max_rows" => 42})

      assert post(body, call_headers([{"mcp-param-maxrows", "42.0"}])).status == 200
      assert post(body, call_headers([{"mcp-param-maxrows", "42"}])).status == 200
    end

    test "a header that is not a numeric literal does not match an integer body value" do
      body = call_body(%{"max_rows" => 42})

      # `" 42"` and `"42 "` were here and are gone: measured against a real Bandit listener, an
      # HTTP/1 parser strips leading OWS, so `" 42"` cannot arrive as a distinct spelling and the
      # row pinned Plug.Test rather than the grammar. `"42 "` does survive the parser, but both
      # belong to a socket-level probe rather than to this one.
      #
      # `"042"` and `"0042"` are here because they were the hole: the comment beside the regex
      # called it JSON's grammar and JSON forbids leading zeros, while the regex admitted them.
      for header <- ["0x2A", "4_2", "", "42abc", "+42", "042", "0042", "00000000000000042"] do
        conn = post(body, call_headers([{"mcp-param-maxrows", header}]))

        assert conn.status == 400,
               "#{inspect(header)} is not a spelling of 42 and must not match it"
      end
    end
  end

  describe "an x-mcp-header annotation the specification forbids is the host's fault" do
    # "x-mcp-header MUST only be applied to parameters with primitive types (integer, string,
    # boolean)" -- quoted in this module's own comment at http.ex:439-441, beside a catch-all
    # that assumed it rather than checking it.
    #
    # A host that annotates a `number` has made an easy mistake: the spec names `integer`, and
    # JSON Schema's neighbouring type is `number`. What the transport did with it was refuse
    # every call to that tool, in both directions -- omit the header and it is "required: the
    # body carries a value to mirror", supply one and it "does not match the corresponding
    # request body value" -- so the tool is advertised in tools/list, is permanently uncallable,
    # and the 400 blames the caller for the host's schema.

    defmodule FloatAnnotationCatalog do
      @behaviour BeamMCP.ToolCatalog
      @impl true
      def all do
        [
          %BeamMCP.ToolSpec{
            name: :echo,
            command_class: :observe,
            mode: :read_only,
            description: "Echo.",
            input_schema: %{
              "type" => "object",
              "properties" => %{"ratio" => %{"type" => "number", "x-mcp-header" => "Ratio"}}
            }
          }
        ]
      end
    end

    defmodule ObjectAnnotationCatalog do
      @behaviour BeamMCP.ToolCatalog
      @impl true
      def all do
        [
          %BeamMCP.ToolSpec{
            name: :echo,
            command_class: :observe,
            mode: :read_only,
            description: "Echo.",
            input_schema: %{
              "type" => "object",
              "properties" => %{
                "obj" => %{
                  "type" => "object",
                  "x-mcp-header" => "Obj",
                  "properties" => %{"k" => %{"type" => "string"}}
                }
              }
            }
          }
        ]
      end
    end

    test "an annotated `number` property is answered as a host fault, not as the caller's error" do
      me = self()

      o =
        opts(
          tool_catalog: FloatAnnotationCatalog,
          dispatch: fn n, a, _ -> send(me, {:dispatched, n, a}) && {:ok, a} end
        )

      body = call_body(%{"ratio" => 1.5})

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          conn = post(body, call_headers([{"mcp-param-ratio", "1.5"}]), o)

          assert conn.status == 500,
                 "a schema the specification forbids is the host's bug. Refusing the caller " <>
                   "with 400 tells them to fix a header they wrote correctly, and no header " <>
                   "they can write will ever satisfy it."

          assert body!(conn)["error"]["code"] == -32_603
          assert body!(conn)["error"]["message"] == "Internal error"

          # The caller learns nothing about the host's schema: not the property, not the
          # annotation name, not the value they sent.
          refute conn.resp_body =~ "ratio"
          refute conn.resp_body =~ "Ratio"
          refute conn.resp_body =~ "1.5"
        end)

      # The diagnosis goes where the party who can fix it will see it.
      assert log =~ "Ratio"
      assert log =~ "echo"

      refute_receive {:dispatched, _, _}, 50
    end

    test "the refusal does not depend on the caller sending the header" do
      # Both directions were closed before, and both must now land on the same answer: the
      # verdict is a property of the SCHEMA, so it cannot depend on what the caller sent.
      o = opts(tool_catalog: FloatAnnotationCatalog)

      ExUnit.CaptureLog.capture_log(fn ->
        assert post(call_body(%{"ratio" => 1.5}), call_headers([]), o).status == 500
      end)
    end

    test "an annotated `object` property is the same fault" do
      o = opts(tool_catalog: ObjectAnnotationCatalog)

      ExUnit.CaptureLog.capture_log(fn ->
        conn = post(call_body(%{"obj" => %{"k" => "v"}}), call_headers([]), o)

        assert conn.status == 500
        assert body!(conn)["error"]["code"] == -32_603
      end)
    end

    test "a property with no declared type is left alone" do
      # The scope limit, pinned so it cannot be widened by accident. A property carrying no
      # "type" cannot be judged from the schema, and judging it on the caller's VALUE instead
      # would turn a caller sending the wrong shape into a host fault -- the wrong side of the
      # boundary, and the mistake this fix exists to stop making in the other direction.
      defmodule UntypedAnnotationCatalog do
        @behaviour BeamMCP.ToolCatalog
        @impl true
        def all do
          [
            %BeamMCP.ToolSpec{
              name: :echo,
              command_class: :observe,
              mode: :read_only,
              description: "Echo.",
              input_schema: %{
                "type" => "object",
                "properties" => %{"loose" => %{"x-mcp-header" => "Loose"}}
              }
            }
          ]
        end
      end

      o = opts(tool_catalog: UntypedAnnotationCatalog)
      body = call_body(%{"loose" => "v"})

      assert post(body, call_headers([{"mcp-param-loose", "v"}]), o).status == 200
      assert post(body, call_headers([{"mcp-param-loose", "other"}]), o).status == 400
    end
  end
end
