# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.ArgumentsSchemaAndFaultsTest do
  @moduledoc """
  0.10.1's fixes, each pinned by the behaviour a client or a host can observe:

  - JSON `true`, `false` and `null` reach dispatch as `true`, `false` and `nil`, never as the
    strings `"true"`, `"false"` and `"nil"`.
  - The schema a tool advertises is enforced at every depth, and a keyword the server would not
    enforce is refused (at startup, and at call time), never advertised and then ignored.
  - On stdio nothing but protocol messages reaches standard output; the transport's reports go
    to standard error; a response the encoder refuses is answered `-32603` and the loop goes on.
  - A client-facing `-32603` names the broken contract, never the host's module or its term.
  - The pagination cursor is read by the wire's one JSON reader.
  - The HTTP transport logs arities, never a hook's arguments (the conn, the body).
  - A `method` or tool `name` that is not a string is refused by name, not raised on.
  """
  use ExUnit.Case, async: false

  import Plug.Test
  import Plug.Conn
  import ExUnit.CaptureIO
  import ExUnit.CaptureLog

  alias BeamMCP.{Cursor, Server}
  alias BeamMCP.Transport.{HTTP, Stdio}

  @meta %{
    "io.modelcontextprotocol/protocolVersion" => "2026-07-28",
    "io.modelcontextprotocol/clientCapabilities" => %{}
  }

  defmodule Catalog do
    @behaviour BeamMCP.Catalog

    @nested %{
      "type" => "object",
      "additionalProperties" => false,
      "properties" => %{
        "dry_run" => %{"type" => "boolean"},
        "note" => %{"type" => ["string", "null"]},
        "opts" => %{
          "type" => "object",
          "additionalProperties" => false,
          "required" => ["mode"],
          "properties" => %{"mode" => %{"type" => "string", "enum" => ["safe"]}}
        },
        "q" => %{"type" => "string", "maxLength" => 3, "pattern" => "^[a-z]+$"},
        "tags" => %{"type" => "array", "items" => %{"type" => "string"}, "maxItems" => 2},
        "flags" => %{"type" => "array", "items" => %{"type" => "boolean"}}
      }
    }

    @impl true
    def capabilities do
      %{
        tools: [
          %BeamMCP.ToolSpec{
            name: :t,
            command_class: :observe,
            mode: :read_only,
            description: "t",
            input_schema: @nested
          }
        ],
        resources: [
          %BeamMCP.ResourceSpec{uri: "r://odd", name: "odd"},
          %BeamMCP.ResourceSpec{uri: "r://baditem", name: "baditem"}
        ],
        prompts: []
      }
    end

    @impl true
    def read_resource("r://odd"), do: {:weird, %{db_url: "postgres://admin:HOSTSECRET@db"}}
    def read_resource("r://baditem"), do: {:ok, [%{token: "ITEMSECRET"}]}
  end

  # A catalog whose answer can change after startup: capabilities/0 runs in the calling
  # process, so the schema is read from its dictionary on every call.
  defmodule ChangingCatalog do
    @behaviour BeamMCP.Catalog

    @impl true
    def capabilities do
      %{
        tools: [
          %BeamMCP.ToolSpec{
            name: :later,
            command_class: :observe,
            mode: :read_only,
            description: "l",
            input_schema: Process.get(:later_schema, %{"type" => "object"})
          }
        ],
        resources: [],
        prompts: []
      }
    end
  end

  defmodule OneOfCatalog do
    @behaviour BeamMCP.Catalog

    @impl true
    def capabilities do
      %{
        tools: [
          %BeamMCP.ToolSpec{
            name: :either,
            command_class: :observe,
            mode: :read_only,
            description: "e",
            input_schema: %{"type" => "object", "oneOf" => [%{"required" => ["a"]}]}
          }
        ],
        resources: [],
        prompts: []
      }
    end
  end

  defp state(dispatch \\ nil) do
    me = self()

    Server.new(
      catalog: Catalog,
      dispatch:
        dispatch ||
          fn _name, args, _opts ->
            send(me, {:dispatched, args})
            {:ok, %{"echo" => args}}
          end
    )
  end

  defp call(arguments, st \\ state()) do
    message = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "tools/call",
      "params" => %{"name" => "t", "arguments" => arguments, "_meta" => @meta}
    }

    {_state, response} = Server.handle_message(st, message)
    response
  end

  defp dispatched do
    receive do
      {:dispatched, args} -> {:dispatched, args}
    after
      100 -> :not_dispatched
    end
  end

  describe "JSON booleans and null reach dispatch as themselves" do
    test "false is false, true is true, null is nil, at the top level and nested" do
      call(%{"dry_run" => false, "note" => nil, "flags" => [true, false]})

      assert {:dispatched, %{dry_run: false, note: nil, flags: [true, false]}} = dispatched()
    end

    test "a host result carrying booleans and nil goes out as JSON booleans and null" do
      response = call(%{"dry_run" => true})
      assert %{"result" => %{"structuredContent" => %{"echo" => %{"dry_run" => true}}}} = response
    end
  end

  describe "the advertised schema is enforced at every depth" do
    test "a nested additionalProperties: false is refused, naming the path" do
      response = call(%{"opts" => %{"mode" => "safe", "evil" => 1}})
      assert :not_dispatched = dispatched()
      assert %{"result" => %{"isError" => true} = result} = response
      assert inspect(result) =~ "opts.evil"
    end

    test "a nested required and a nested enum are refused" do
      call(%{"opts" => %{}})
      assert :not_dispatched = dispatched()
      call(%{"opts" => %{"mode" => "unsafe"}})
      assert :not_dispatched = dispatched()
    end

    test "maxLength, pattern, items and maxItems are refused" do
      for args <- [
            %{"q" => "abcd"},
            %{"q" => "AB"},
            %{"tags" => ["a", 1]},
            %{"tags" => ["a", "b", "c"]}
          ] do
        call(args)
        assert :not_dispatched = dispatched(), "dispatched #{inspect(args)}"
      end
    end

    test "a call that meets the whole schema is dispatched" do
      call(%{"opts" => %{"mode" => "safe"}, "q" => "abc", "tags" => ["x"]})
      assert {:dispatched, %{opts: %{"mode" => "safe"}, q: "abc", tags: ["x"]}} = dispatched()
    end

    test "additionalProperties as a schema checks every undeclared property, naming its path" do
      schema = %{
        "type" => "object",
        "properties" => %{"a" => %{"type" => "string"}},
        "additionalProperties" => %{"type" => "integer"}
      }

      assert {:error, reason} = BeamMCP.Schema.validate(%{"a" => "x", "extra" => "no"}, schema)
      assert reason =~ "extra must be of type integer"
      assert :ok = BeamMCP.Schema.validate(%{"a" => "x", "extra" => 1}, schema)
    end

    test "a list-form type refuses a value of none of its types" do
      call(%{"note" => 1})
      assert :not_dispatched = dispatched()
      call(%{"note" => "fine"})
      assert {:dispatched, %{note: "fine"}} = dispatched()
    end

    test "every keyword the README lists is accepted with a well-formed value" do
      for {key, value} <- [
            {"type", "object"},
            {"enum", [1]},
            {"const", 1},
            {"properties", %{}},
            {"required", []},
            {"additionalProperties", false},
            {"minProperties", 0},
            {"maxProperties", 1},
            {"items", %{}},
            {"minItems", 0},
            {"maxItems", 1},
            {"uniqueItems", true},
            {"minLength", 0},
            {"maxLength", 1},
            {"pattern", "^a$"},
            {"minimum", 0},
            {"maximum", 1},
            {"exclusiveMinimum", 0},
            {"exclusiveMaximum", 1}
          ] do
        assert :ok = BeamMCP.Schema.check_schema(%{key => value}), key
      end
    end

    test "a schema that becomes unenforceable after startup is a server fault (-32603), never blamed on the client" do
      st = Server.new(catalog: ChangingCatalog, dispatch: fn _, a, _ -> {:ok, a} end)
      Process.put(:later_schema, %{"type" => "object", "oneOf" => []})

      {_state, response} =
        Server.handle_message(st, %{
          "jsonrpc" => "2.0",
          "id" => 5,
          "method" => "tools/call",
          "params" => %{"name" => "later", "arguments" => %{}, "_meta" => @meta}
        })

      assert %{"id" => 5, "error" => %{"code" => -32_603, "message" => message}} = response
      assert message =~ "tool later"
      assert message =~ "oneOf"
      refute Map.has_key?(response, "result")
    after
      Process.delete(:later_schema)
    end

    test "a schema using a keyword the server does not enforce is refused at startup, by name" do
      error = assert_raise ArgumentError, fn -> Server.new(catalog: OneOfCatalog) end
      assert error.message =~ "oneOf"
    end

    test "each numeric bound refuses the value on its wrong side, and only there" do
      schema = fn key, bound ->
        %{"type" => "object", "properties" => %{"n" => %{"type" => "number", key => bound}}}
      end

      for {key, refused, passed} <- [
            {"minimum", 4, 5},
            {"maximum", 6, 5},
            {"exclusiveMinimum", 5, 6},
            {"exclusiveMaximum", 5, 4}
          ] do
        assert {:error, reason} = BeamMCP.Schema.validate(%{"n" => refused}, schema.(key, 5))
        assert reason =~ "n must be"
        assert :ok = BeamMCP.Schema.validate(%{"n" => passed}, schema.(key, 5)), key
      end
    end

    test "pattern reads ECMA-262's classes and anchors: no match before a trailing newline, ASCII digits only" do
      only = fn pattern -> %{"properties" => %{"a" => %{"pattern" => pattern}}} end

      assert {:error, _} = BeamMCP.Schema.validate(%{"a" => "abc\n"}, only.("^[a-z]+$"))
      assert {:error, _} = BeamMCP.Schema.validate(%{"a" => "٣"}, only.("^\\d$"))
      assert {:error, _} = BeamMCP.Schema.validate(%{"a" => "\u00a0"}, only.("^\\s$"))

      # \w is ASCII from OTP 28 (PCRE2). OTP 27's :re is PCRE with Latin-1 tables and offers no
      # ASCII ones, so there \w also takes U+00AA to U+00FF, as the moduledoc states; nothing
      # outside Latin-1 on either (measured on 27, 28 and 29).
      assert {:error, _} = BeamMCP.Schema.validate(%{"a" => "Ā"}, only.("^\\w$"))

      if String.to_integer(System.otp_release()) >= 28,
        do: assert({:error, _} = BeamMCP.Schema.validate(%{"a" => "é"}, only.("^\\w$"))),
        else: assert(:ok = BeamMCP.Schema.validate(%{"a" => "é"}, only.("^\\w$")))

      assert :ok = BeamMCP.Schema.validate(%{"a" => "abc"}, only.("^[a-z]+$"))
      assert :ok = BeamMCP.Schema.validate(%{"a" => "é"}, only.("^.$"))
    end

    test "lengths count code points, not bytes; every count bound refuses on its side only" do
      at = fn sub -> %{"properties" => %{"a" => sub}} end
      v = &BeamMCP.Schema.validate(%{"a" => &1}, at.(&2))

      # "héé" is 3 code points and 5 bytes; "é" is 1 code point and 2 bytes.
      assert :ok = v.("héé", %{"maxLength" => 3})
      assert {:error, _} = v.("héél", %{"maxLength" => 3})
      assert {:error, _} = v.("é", %{"minLength" => 2})
      assert :ok = v.("éé", %{"minLength" => 2})

      assert {:error, _} = v.([1], %{"minItems" => 2})
      assert :ok = v.([1, 2], %{"minItems" => 2})
      assert {:error, _} = v.(%{}, %{"minProperties" => 1})
      assert :ok = v.(%{"k" => 1}, %{"minProperties" => 1})
      assert {:error, _} = v.(%{"k" => 1, "l" => 2}, %{"maxProperties" => 1})
      assert :ok = v.(%{"k" => 1}, %{"maxProperties" => 1})

      assert {:error, reason} = v.([1, 1], %{"uniqueItems" => true})
      assert reason =~ "a must not repeat items"
      assert :ok = v.([1, 1], %{"uniqueItems" => false})
      assert :ok = v.([1, 2], %{"uniqueItems" => true})
    end

    test "enum, const and uniqueItems compare as JSON: 1 is 1.0, at any depth" do
      at = fn sub -> %{"properties" => %{"a" => sub}} end

      assert :ok = BeamMCP.Schema.validate(%{"a" => 1}, at.(%{"enum" => [1.0]}))
      assert :ok = BeamMCP.Schema.validate(%{"a" => [1.0]}, at.(%{"const" => [1]}))
      assert {:error, _} = BeamMCP.Schema.validate(%{"a" => 2}, at.(%{"const" => 1.0}))

      assert {:error, reason} =
               BeamMCP.Schema.validate(%{"a" => [1, 1.0]}, at.(%{"uniqueItems" => true}))

      assert reason =~ "must not repeat items"

      assert {:error, _} =
               BeamMCP.Schema.validate(
                 %{"a" => [%{"n" => 2}, %{"n" => 2.0}]},
                 at.(%{"uniqueItems" => true})
               )

      assert :ok = BeamMCP.Schema.validate(%{"a" => [1, 1.5]}, at.(%{"uniqueItems" => true}))
    end

    test "a property name that is not a string, and an enum or const that is not JSON, are refused, never raised" do
      for schema <- [
            %{"properties" => %{mode: %{"type" => "string"}}},
            %{"properties" => %{1 => %{}}},
            %{"properties" => %{{:a, 1} => %{}}},
            %{{:a, 1} => true},
            %{"properties" => %{"a" => %{"enum" => [{:a, 1}]}}},
            %{"properties" => %{"a" => %{"const" => {:a}}}},
            %{"properties" => %{"a" => %{"enum" => [1 | 2]}}},
            %{"required" => ["a" | :b]},
            %{"type" => ["string" | "null"]},
            %{"properties" => %{"a" => ~r/x/}}
          ] do
        assert {:error, reason} = BeamMCP.Schema.check_schema(schema), inspect(schema)
        assert is_binary(reason)
        assert {:error, _} = BeamMCP.Schema.validate(%{"a" => "x"}, schema)
      end
    end

    test "and refused at call time, never dispatched, if it arrives after startup" do
      assert {:error, reason} = BeamMCP.Schema.validate(%{"a" => 1}, %{"oneOf" => []})
      assert reason =~ "oneOf"
    end
  end

  describe "stdio: standard output carries protocol messages only" do
    # The device is opened as latin1 so the transport reads the input's raw bytes, byte for
    # byte, as it reads a real pipe (the file is UTF-8 throughout; this is the device's mode,
    # not the text's).
    defp drive(input, opts) do
      {:ok, device} = StringIO.open(input, encoding: :latin1)
      original = Process.group_leader()
      Process.group_leader(self(), device)

      stderr =
        try do
          capture_io(:stderr, fn -> Stdio.run(opts) end)
        after
          Process.group_leader(self(), original)
        end

      {:ok, {_input, stdout}} = StringIO.close(device)
      {stdout, stderr}
    end

    defp lines(stdout), do: stdout |> String.split("\n", trim: true)

    test "a fault's report goes to standard error, and every stdout line is a JSON-RPC message" do
      input =
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "tools/call",
          "params" => %{"name" => "t", "arguments" => %{}}
        }) <>
          "\n" <>
          ~s({"jsonrpc":"2.0","id":2,"method":"ping"}\n)

      {stdout, stderr} =
        drive(input, catalog: Catalog, dispatch: fn _, _, _ -> raise "HOSTFAULT" end)

      assert Enum.all?(lines(stdout), &match?({:ok, %{"jsonrpc" => "2.0"}}, Jason.decode(&1)))

      assert [%{"id" => 1, "error" => %{"code" => -32_603}}, %{"id" => 2}] =
               Enum.map(lines(stdout), &Jason.decode!/1)

      assert stderr =~ "HOSTFAULT"
    end

    test "a response the encoder refuses is answered -32603 with its id, and the loop goes on" do
      input =
        Jason.encode!(%{
          "jsonrpc" => "2.0",
          "id" => 7,
          "method" => "tools/call",
          "params" => %{"name" => "t", "arguments" => %{}}
        }) <>
          "\n" <>
          ~s({"jsonrpc":"2.0","id":8,"method":"ping"}\n)

      {stdout, stderr} =
        drive(input,
          catalog: Catalog,
          dispatch: fn _, _, _ -> {:error, "HOSTSECRET" <> <<0xFF, 0xFE>>} end
        )

      assert [%{"id" => 7, "error" => %{"code" => -32_603}}, %{"id" => 8, "result" => %{}}] =
               Enum.map(lines(stdout), &Jason.decode!/1)

      # The report names the exception, not the bytes the encoder refused: they are the host's.
      assert stderr =~ "Jason.EncodeError"
      refute stderr =~ "HOSTSECRET"
      refute stderr =~ "72, 79, 83, 84"
    end
  end

  describe "a client-facing -32603 names the contract, never the host's term" do
    defp read(uri) do
      {_state, response} =
        Server.handle_message(state(), %{
          "jsonrpc" => "2.0",
          "id" => 3,
          "method" => "resources/read",
          "params" => %{"uri" => uri, "_meta" => @meta}
        })

      response
    end

    test "a reader answering an off-contract shape" do
      message = get_in(read("r://odd"), ["error", "message"])
      assert message =~ "read_resource/1"
      refute message =~ "HOSTSECRET"
      refute message =~ inspect(Catalog)
    end

    test "a reader returning an item without a uri" do
      message = get_in(read("r://baditem"), ["error", "message"])
      assert message =~ "read_resource/1"
      refute message =~ "ITEMSECRET"
    end
  end

  describe "the pagination cursor is read by the wire's one JSON reader" do
    test "a cursor that repeats a key is malformed, as a body that does is refused" do
      json = ~s({"v":1,"k":"resources","a":"x","a":"y"})

      assert {:error, :malformed} =
               Cursor.decode(:resources, Base.url_encode64(json, padding: false))
    end

    test "a cursor nested past the bound is malformed" do
      json = String.duplicate("[", 65) <> String.duplicate("]", 65)

      assert {:error, :malformed} =
               Cursor.decode(:resources, Base.url_encode64(json, padding: false))
    end
  end

  describe "the HTTP transport logs arities, never a hook's arguments" do
    defmodule Hooks do
      def authorize(%{method: "GET"}), do: :ok
    end

    test "a hook that raises function_clause: the Authorization header and the body stay out of the log" do
      opts =
        HTTP.init(
          catalog: Catalog,
          dispatch: fn _, a, _ -> {:ok, a} end,
          authorize: &Hooks.authorize/1,
          allowed_origins: :any
        )

      body = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "ping",
        "params" => %{"_meta" => @meta, "marker" => "BODYMARKER"}
      }

      log =
        capture_log(fn ->
          conn =
            conn(:post, "/mcp", Jason.encode!(body))
            |> put_req_header("content-type", "application/json")
            |> put_req_header("authorization", "Bearer TOKENMARKER")
            |> put_req_header("mcp-protocol-version", "2026-07-28")
            |> put_req_header("mcp-method", "ping")
            |> HTTP.call(opts)

          assert conn.status == 500
        end)

      assert log =~ "FunctionClauseError"
      refute log =~ "TOKENMARKER"
      refute log =~ "BODYMARKER"
    end
  end

  describe "a method or tool name that is not a string is refused by name" do
    defp handle(message), do: Server.handle_message(state(), message) |> elem(1)

    test "an object method is Invalid Request" do
      assert %{"error" => %{"code" => -32_600}} =
               handle(%{"jsonrpc" => "2.0", "id" => 1, "method" => %{"m" => 1}})
    end

    test "a JSON true, an object or a missing name on tools/call is invalid params" do
      for params <- [%{"name" => true}, %{"name" => %{"x" => 1}}, %{}] do
        response =
          handle(%{
            "jsonrpc" => "2.0",
            "id" => 1,
            "method" => "tools/call",
            "params" => Map.put(params, "_meta", @meta)
          })

        assert %{"error" => %{"code" => -32_602}} = response, inspect(params)
      end

      assert :not_dispatched = dispatched()
    end

    test "initialize with params that are not an object is answered, not raised on" do
      assert %{"id" => 1} =
               handle(%{"jsonrpc" => "2.0", "id" => 1, "method" => "initialize", "params" => [1]})
    end
  end
end
