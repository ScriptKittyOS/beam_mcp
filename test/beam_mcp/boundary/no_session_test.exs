# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Boundary.NoSessionTest do
  # boundary: no session identifiers
  # Over HTTP every request stands alone: no response carries an `mcp-session-id` header, a
  # request that carries one is answered exactly as one that does not, and no code line under
  # lib/ reads or writes a session identifier.
  use ExUnit.Case, async: true
  import Plug.Test
  import Plug.Conn
  alias BeamMCP.Transport.HTTP

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

  @meta %{
    "io.modelcontextprotocol/protocolVersion" => "2026-07-28",
    "io.modelcontextprotocol/clientCapabilities" => %{}
  }

  defp opts,
    do:
      HTTP.init(
        catalog: Catalog,
        dispatch: fn _, _, _ -> {:ok, %{}} end,
        authorize: fn _ -> :ok end,
        allowed_origins: :any
      )

  defp post(body, extra_headers) do
    headers =
      [{"mcp-protocol-version", "2026-07-28"}, {"mcp-method", body["method"]}] ++ extra_headers

    headers =
      if body["method"] == "tools/call", do: headers ++ [{"mcp-name", "echo"}], else: headers

    Enum.reduce(
      headers,
      conn(:post, "/", Jason.encode!(body)) |> put_req_header("content-type", "application/json"),
      fn {k, v}, c ->
        put_req_header(c, k, v)
      end
    )
    |> HTTP.call(opts())
  end

  @requests [
    %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "server/discover",
      "params" => %{"_meta" => @meta}
    },
    %{"jsonrpc" => "2.0", "id" => 2, "method" => "tools/list", "params" => %{"_meta" => @meta}},
    %{
      "jsonrpc" => "2.0",
      "id" => 3,
      "method" => "tools/call",
      "params" => %{"name" => "echo", "arguments" => %{}, "_meta" => @meta}
    },
    %{"jsonrpc" => "2.0", "id" => 4, "method" => "nope", "params" => %{"_meta" => @meta}}
  ]

  test "no response carries an mcp-session-id header, and a request carrying one is answered as if it did not" do
    for body <- @requests do
      plain = post(body, [])
      with_session = post(body, [{"mcp-session-id", "sess-1234"}])
      assert get_resp_header(plain, "mcp-session-id") == [], body["method"]
      assert get_resp_header(with_session, "mcp-session-id") == [], body["method"]

      assert {plain.status, plain.resp_body} == {with_session.status, with_session.resp_body},
             body["method"]
    end
  end

  test "no code line under lib/ reads or writes a session identifier" do
    # The header name in any delimiter, or a session-id variable; the one allowance is the
    # transport's own denial, "no `Mcp-Session-Id`", by that exact phrase -- a backticked name
    # inside a string is still a hit.
    hits = BeamMCP.Boundary.hits(~r/(?<!no `)mcp-session-id|session_id|:mcp_session/i)
    assert hits == [], "session identifiers under lib/:\n  " <> BeamMCP.Boundary.format(hits)
  end
end
