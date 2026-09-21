# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Transport.ServerSeamTest do
  @moduledoc """
  The `:server` seam, proved by effect on both transports: with the option omitted the core
  answers, as it did before the option existed; with a wrapper passed, the wrapper answers the
  one method it takes and the core answers the rest through it; a module that is not a server
  is refused at init, naming the functions the transport reaches through it. The wrapper's
  state is its own map, so a transport that read the state would show here.
  """
  # Stdio is driven through the group leader (see BeamMCP.Transport.StdioTest), so not async.
  use ExUnit.Case, async: false

  import Plug.Test, only: [conn: 3]
  import Plug.Conn, only: [put_req_header: 3]

  alias BeamMCP.Fixture.ServerWrapper
  alias BeamMCP.Transport.HTTP
  alias BeamMCP.Transport.Stdio

  @modern "2026-07-28"
  @meta %{
    "io.modelcontextprotocol/protocolVersion" => @modern,
    "io.modelcontextprotocol/clientCapabilities" => %{}
  }

  defmodule Catalog do
    @behaviour BeamMCP.Catalog
    @impl true
    def capabilities do
      %{
        tools: [
          %BeamMCP.ToolSpec{
            name: :echo,
            command_class: :observe,
            mode: :read_only,
            description: "Echo."
          }
        ],
        resources: [],
        prompts: []
      }
    end
  end

  # The dispatch tells the test process it ran: a wrapper that answers `tools/call` itself
  # must leave it silent.
  defp dispatch(name, args, _opts) do
    send(self(), {:dispatched, name})
    {:ok, args}
  end

  defp core_opts, do: [catalog: Catalog, dispatch: &dispatch/3]

  # The echo tool declares no schema, so its arguments are none: the core's answer is `{}`
  # through dispatch, and the wrapper's is its own text -- two answers a test can tell apart.
  defp call(id) do
    %{
      "jsonrpc" => "2.0",
      "id" => id,
      "method" => "tools/call",
      "params" => %{"name" => "echo", "arguments" => %{}, "_meta" => @meta}
    }
  end

  defp list(id),
    do: %{
      "jsonrpc" => "2.0",
      "id" => id,
      "method" => "tools/list",
      "params" => %{"_meta" => @meta}
    }

  # --- HTTP -------------------------------------------------------------------------------

  defp http_init(extra \\ []) do
    HTTP.init(core_opts() ++ [authorize: fn _ -> :ok end, allowed_origins: :any] ++ extra)
  end

  defp post(body, plug_opts) do
    headers = [{"mcp-protocol-version", @modern}, {"mcp-method", body["method"]}]

    headers =
      case body do
        %{"params" => %{"name" => name}} -> headers ++ [{"mcp-name", name}]
        _ -> headers
      end

    conn =
      :post
      |> conn("/mcp", Jason.encode!(body))
      |> put_req_header("content-type", "application/json")

    conn = Enum.reduce(headers, conn, fn {k, v}, c -> put_req_header(c, k, v) end)
    conn = HTTP.call(conn, plug_opts)
    {conn.status, Jason.decode!(conn.resp_body)}
  end

  describe "over HTTP" do
    test "with :server omitted the core answers and dispatch runs: the default is BeamMCP.Server" do
      {200, body} = post(call(1), http_init())
      assert [%{"type" => "text", "text" => "{}"}] = body["result"]["content"]
      assert_received {:dispatched, :echo}
      refute_received {:wrapper_new, _}
    end

    test "with a wrapper passed, tools/call is the wrapper's and dispatch never runs" do
      {200, body} = post(call(1), http_init(server: ServerWrapper.Answers))

      assert body["result"]["content"] == [
               %{"type" => "text", "text" => "answered by the wrapper"}
             ]

      refute_received {:dispatched, _}
    end

    test "the wrapper's new/1 receives the core's options and not :server, which is the Plug's" do
      _ = post(list(1), http_init(server: ServerWrapper.Answers))
      assert_received {:wrapper_new, opts}
      refute Keyword.has_key?(opts, :server)
      assert opts[:catalog] == Catalog
      assert opts[:supported_versions] == [@modern]
    end

    test "every other method is delegated: the wrapper's tools/list is the default's, byte for byte" do
      {200, default} = post(list(1), http_init())
      {200, wrapped} = post(list(1), http_init(server: ServerWrapper.Answers))
      assert Jason.encode!(wrapped) == Jason.encode!(default)
    end

    test "a wrapper exporting new/1 and handle_message/2 alone is enough for HTTP, which never asks shutdown?/1" do
      {200, body} = post(call(1), http_init(server: ServerWrapper.TwoOnly))
      assert [%{"type" => "text", "text" => "{}"}] = body["result"]["content"]
      assert_received {:dispatched, :echo}
    end

    test "a module that is not a server is refused at init, naming both functions" do
      error = assert_raise ArgumentError, fn -> http_init(server: ServerWrapper.NotAServer) end
      assert error.message =~ ":server"
      assert error.message =~ "new/1"
      assert error.message =~ "handle_message/2"
      assert error.message =~ "BeamMCP.Fixture.ServerWrapper.NotAServer"
    end

    test "a module with the names at the wrong arities is refused at init" do
      assert_raise ArgumentError, ~r/new\/1/, fn ->
        http_init(server: ServerWrapper.WrongArity)
      end
    end

    test "each function is checked on its own: a module lacking only new/1, or only handle_message/2, is refused" do
      # Both fixtures export shutdown?/1 and one of the two HTTP reaches, so only the check for
      # the missing one can refuse them; a list that drops a name lets one of them through.
      for server <- [ServerWrapper.NewOnly, ServerWrapper.HandleOnly] do
        error = assert_raise ArgumentError, fn -> http_init(server: server) end
        assert error.message =~ inspect(server)
      end
    end

    test "a value that is not a module is refused at init" do
      assert_raise ArgumentError, ~r/:server/, fn -> http_init(server: "BeamMCP.Server") end
      assert_raise ArgumentError, ~r/:server/, fn -> http_init(server: nil) end
    end
  end

  # --- stdio ------------------------------------------------------------------------------

  # The real loop over a StringIO standing in for stdio, as BeamMCP.Transport.StdioTest drives it.
  defp drive(input, opts) do
    {:ok, device} = StringIO.open(input, encoding: :latin1)
    original = Process.group_leader()
    Process.group_leader(self(), device)

    try do
      Stdio.run(opts)
    after
      Process.group_leader(self(), original)
    end

    {:ok, {_input, output}} = StringIO.close(device)
    output |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)
  end

  defp line(message), do: Jason.encode!(message) <> "\n"

  describe "over stdio" do
    test "with :server omitted the core answers and dispatch runs" do
      [body] = drive(line(call(1)), core_opts())
      assert [%{"type" => "text", "text" => "{}"}] = body["result"]["content"]
      assert_received {:dispatched, :echo}
    end

    test "with a wrapper passed, tools/call is the wrapper's, the rest is the core's, and the loop ends when the wrapper says so" do
      input =
        line(call(1)) <>
          line(list(2)) <>
          line(%{"jsonrpc" => "2.0", "id" => 3, "method" => "shutdown"}) <>
          line(call(4))

      [first, second, third] = drive(input, core_opts() ++ [server: ServerWrapper.Answers])

      assert first["result"]["content"] == [
               %{"type" => "text", "text" => "answered by the wrapper"}
             ]

      refute_received {:dispatched, _}

      [default_list] = drive(line(list(2)), core_opts())
      assert Jason.encode!(second) == Jason.encode!(default_list)

      # `shutdown` reached the core through the wrapper, the wrapper's shutdown?/1 said so, and
      # the fourth message was never read: three responses, not four.
      assert third == %{"jsonrpc" => "2.0", "id" => 3, "result" => %{}}
    end

    test "the wrapper's new/1 receives the core's options and not :server" do
      _ = drive("", core_opts() ++ [server: ServerWrapper.Answers])
      assert_received {:wrapper_new, opts}
      refute Keyword.has_key?(opts, :server)
      assert opts[:catalog] == Catalog
    end

    test "stdio reaches shutdown?/1 too, so a module without it is refused at init, by name" do
      error =
        assert_raise ArgumentError, fn ->
          drive("", core_opts() ++ [server: ServerWrapper.TwoOnly])
        end

      assert error.message =~ "shutdown?/1"
      assert error.message =~ "BeamMCP.Fixture.ServerWrapper.TwoOnly"
    end

    test "a module that is not a server is refused before a byte is read, naming the three functions" do
      error =
        assert_raise ArgumentError, fn ->
          drive(line(call(1)), core_opts() ++ [server: ServerWrapper.NotAServer])
        end

      assert error.message =~ "new/1"
      assert error.message =~ "handle_message/2"
      assert error.message =~ "shutdown?/1"
      refute_received {:dispatched, _}
    end

    test "a module with the names at the wrong arities is refused at init" do
      assert_raise ArgumentError, ~r/new\/1/, fn ->
        drive("", core_opts() ++ [server: ServerWrapper.WrongArity])
      end
    end

    test "each function is checked on its own: a module lacking only new/1, or only handle_message/2, is refused" do
      for server <- [ServerWrapper.NewOnly, ServerWrapper.HandleOnly] do
        error =
          assert_raise ArgumentError, fn -> drive("", core_opts() ++ [server: server]) end

        assert error.message =~ inspect(server)
      end
    end
  end
end
