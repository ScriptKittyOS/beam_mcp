# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.UnservedSubscriptionTest do
  # boundary: advertises no change notification it does not deliver
  # 2026-07-28 replaced `resources/subscribe` with `subscriptions/listen`, a long-lived stream
  # (SEP-2575): `listChanged` on tools, resources or prompts, and `subscribe` on resources, are
  # promises a client can only collect on that stream. This package does not serve it in 1.x
  # (the HTTP transport is stateless by contract; stdio answers one message at a time), so it
  # advertises every one of those flags `false`, and a request for the stream, or for the
  # legacy subscribe, is answered method-not-found: -32601, and 404 over HTTP. A server that
  # advertises neither is conformant (resources.mdx: "Servers may advertise either feature
  # independently, together or neither"). The rule this holds: no flag is advertised `true`
  # while the method that delivers it is not served. Stated on the will-not-implement page,
  # entry 13; implementing the stream later is an addition, and turns this census over with it.
  use ExUnit.Case, async: true

  alias BeamMCP.Server
  alias BeamMCP.Transport.HTTP

  @modern "2026-07-28"
  @legacy "2025-11-25"
  @meta %{
    "io.modelcontextprotocol/protocolVersion" => @modern,
    "io.modelcontextprotocol/clientCapabilities" => %{}
  }

  defmodule Catalog do
    @moduledoc false
    def capabilities, do: %{tools: [], resources: [], prompts: []}
  end

  defp core(message), do: elem(Server.handle_message(Server.new(catalog: Catalog), message), 1)

  defp request(method, params \\ %{}),
    do: %{"jsonrpc" => "2.0", "id" => 1, "method" => method, "params" => params}

  # The change-notification flags a capabilities map advertises, as {capability, flag, value}.
  defp flags(capabilities) do
    for {cap, %{} = sub} <- capabilities,
        {flag, value} <- sub,
        flag in ["listChanged", "subscribe"],
        do: {cap, flag, value}
  end

  defp served?(method, params) do
    case core(request(method, params)) do
      %{"error" => %{"code" => -32_601}} -> false
      _ -> true
    end
  end

  test "no listChanged or subscribe is advertised true while subscriptions/listen is not served" do
    modern = core(request("server/discover", %{"_meta" => @meta}))["result"]["capabilities"]

    legacy =
      core(request("initialize", %{"protocolVersion" => @legacy, "capabilities" => %{}}))[
        "result"
      ]["capabilities"]

    listen = %{"_meta" => @meta, "filter" => %{"resourcesListChanged" => true}}
    refute served?("subscriptions/listen", listen)

    # Every flag the two eras advertise is present and false: the population is what the
    # server wrote, so a capability gaining a flag is read here the day it is advertised.
    for caps <- [modern, legacy] do
      advertised = flags(caps)
      assert advertised != []
      assert Enum.all?(advertised, fn {_, _, value} -> value == false end), inspect(advertised)
    end
  end

  test "subscriptions/listen and resources/subscribe are answered -32601 on the core, and 404 over HTTP" do
    for {method, params} <- [
          {"subscriptions/listen", %{"_meta" => @meta, "filter" => %{}}},
          {"resources/subscribe", %{"_meta" => @meta, "uri" => "r://a"}},
          {"resources/subscribe", %{"uri" => "r://a"}}
        ] do
      assert %{"error" => %{"code" => -32_601}} = core(request(method, params)), method
    end

    opts =
      HTTP.init(
        catalog: Catalog,
        authorize: fn _ -> :ok end,
        allowed_origins: :any
      )

    for method <- ["subscriptions/listen", "resources/subscribe"] do
      body = Jason.encode!(request(method, %{"_meta" => @meta}))

      conn =
        Plug.Test.conn(:post, "/mcp", body)
        |> Plug.Conn.put_req_header("content-type", "application/json")
        |> Plug.Conn.put_req_header("mcp-protocol-version", @modern)
        |> Plug.Conn.put_req_header("mcp-method", method)
        |> HTTP.call(opts)

      assert conn.status == 404, method
      assert %{"error" => %{"code" => -32_601}} = Jason.decode!(conn.resp_body)
    end
  end
end
