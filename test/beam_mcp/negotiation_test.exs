# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.NegotiationTest do
  @moduledoc """
  Two eras, one server.

  `2026-07-28` removed the `initialize` handshake and protocol-level sessions: every request
  carries its version and capabilities in `_meta`, and `server/discover` is mandatory.
  `2025-11-25` and earlier open with `initialize`. The specification calls a server that
  serves both **dual-era**, and states the discriminator:

  > A request carrying modern per-request `_meta` is served statelessly according to this
  > revision. An `initialize` request selects legacy semantics.

  Supported set: `2026-07-28` (modern) and `2025-11-25` (legacy). Two revisions, not five.
  """
  use ExUnit.Case, async: true

  alias BeamMCP.Server

  @modern "2026-07-28"
  @legacy "2025-11-25"

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

  defp state, do: Server.new(tool_catalog: Catalog, dispatch: fn _n, a, _o -> {:ok, a} end)

  defp send_msg(msg), do: state() |> Server.handle_message(msg) |> elem(1)

  defp modern(method, extra \\ %{}) do
    Map.merge(
      %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => method,
        "_meta" => %{
          "io.modelcontextprotocol/protocolVersion" => @modern,
          "io.modelcontextprotocol/clientCapabilities" => %{}
        }
      },
      extra
    )
  end

  describe "server/discover — mandatory in 2026-07-28" do
    test "it exists and advertises the supported versions, capabilities and identity" do
      r = send_msg(%{"jsonrpc" => "2.0", "id" => 1, "method" => "server/discover"})

      refute r["error"], "server/discover is mandatory: servers MUST implement it"
      assert r["result"]["protocolVersions"] == [@modern, @legacy]
      assert r["result"]["serverInfo"]["name"]
      assert is_map(r["result"]["capabilities"])
    end
  end

  describe "the era discriminator" do
    test "a request carrying modern _meta is served as modern, not as legacy" do
      r = send_msg(modern("tools/list"))

      assert r["result"]["resultType"] == "complete",
             "a modern result MUST carry resultType; a legacy-shaped answer to a modern " <>
               "request looks like success and is the defect this slice exists to close"

      assert r["result"]["_meta"]["io.modelcontextprotocol/serverInfo"]
    end

    test "an initialize request selects legacy semantics" do
      r =
        send_msg(%{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "initialize",
          "params" => %{"protocolVersion" => @legacy}
        })

      assert r["result"]["protocolVersion"] == @legacy
      refute r["result"]["resultType"], "legacy results carry no resultType"
    end
  end

  describe "version negotiation" do
    test "initialize is answered with the revision the client asked for, when supported" do
      r =
        send_msg(%{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "initialize",
          "params" => %{"protocolVersion" => @legacy}
        })

      assert r["result"]["protocolVersion"] == @legacy
    end

    test "initialize asking an unsupported revision gets -32022, not a constant" do
      r =
        send_msg(%{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "initialize",
          "params" => %{"protocolVersion" => "2024-11-05"}
        })

      assert r["error"]["code"] == -32_022
      assert r["error"]["data"]["supported"] == [@modern, @legacy]
      assert r["error"]["data"]["requested"] == "2024-11-05"
    end

    test "a modern request declaring an unsupported version gets -32022" do
      msg =
        put_in(
          modern("tools/list"),
          ["_meta", "io.modelcontextprotocol/protocolVersion"],
          "1900-01-01"
        )

      r = send_msg(msg)

      assert r["error"]["code"] == -32_022
      assert r["error"]["data"]["requested"] == "1900-01-01"
    end
  end

  describe "ping — answered at legacy, absent at modern" do
    test "a legacy ping is answered" do
      r = send_msg(%{"jsonrpc" => "2.0", "id" => 1, "method" => "ping"})

      assert r["result"] == %{}
    end

    test "a modern ping is refused: the method does not exist in 2026-07-28" do
      r = send_msg(modern("ping"))

      assert r["error"]["code"] == -32_601,
             "ping was removed in 2026-07-28; the legacy handler must not inherit it"
    end
  end

  describe "JSON-RPC batching — required in exactly one revision, and not ours" do
    test "a batch is refused rather than processed" do
      batch = [
        %{"jsonrpc" => "2.0", "id" => 1, "method" => "ping"},
        %{"jsonrpc" => "2.0", "id" => 2, "method" => "ping"}
      ]

      r = send_msg(batch)

      assert r["error"],
             "batching was added in 2025-03-26 and removed in 2025-06-18; " <>
               "neither supported revision includes it"

      assert r["id"] == nil
    end
  end
end
