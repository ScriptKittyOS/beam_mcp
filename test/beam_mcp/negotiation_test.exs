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
    @behaviour BeamMCP.Catalog

    @impl true
    def capabilities, do: %{tools: all_tools(), resources: [], prompts: []}

    defp all_tools do
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

  defp state, do: Server.new(catalog: Catalog, dispatch: fn _n, a, _o -> {:ok, a} end)

  defp send_msg(msg), do: state() |> Server.handle_message(msg) |> elem(1)

  # send_msg/1 throws the state away, so nothing it drives can catch a branch that returns
  # the wrong state. shutdown is the only request method that changes state and it reaches
  # both era branches, so it is the input that covers them.
  defp send_for_state(msg), do: state() |> Server.handle_message(msg) |> elem(0)

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

  # The same modern carrier, declaring the legacy revision. The specification's own retry
  # advice on -32022 produces exactly this message: pick from `supported` and retry the
  # request. `supported` here is ["2026-07-28", "2025-11-25"].
  defp legacy_meta(method, extra \\ %{}) do
    Map.merge(
      %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => method,
        "_meta" => %{"io.modelcontextprotocol/protocolVersion" => @legacy}
      },
      extra
    )
  end

  describe "server/discover — mandatory in 2026-07-28" do
    test "it exists and advertises the supported versions, capabilities and identity" do
      r = send_msg(%{"jsonrpc" => "2.0", "id" => 1, "method" => "server/discover"})

      refute r["error"], "server/discover is mandatory: servers MUST implement it"
      assert r["result"]["supportedVersions"] == [@modern, @legacy]
      assert r["result"]["_meta"]["io.modelcontextprotocol/serverInfo"]["name"]
      assert is_map(r["result"]["capabilities"])
    end
  end

  describe "server/discover carries the DiscoverResult the 2026-07-28 schema requires" do
    # The schema (2026-07-28, $defs.DiscoverResult) requires cacheScope, capabilities,
    # resultType, supportedVersions and ttlMs, and PR #3002 moved serverInfo out of the body
    # into _meta (a SHOULD). The undecorated discover was a probe shortcut; a client reading
    # it had grounds to classify the server as legacy.
    test "the MUST fields, resultType among them, and serverInfo in _meta, not the body" do
      r = send_msg(%{"jsonrpc" => "2.0", "id" => 1, "method" => "server/discover"})["result"]
      assert r["supportedVersions"] == [@modern, @legacy]
      assert r["capabilities"] == %{"tools" => %{"listChanged" => false}}
      assert r["resultType"] == "complete"
      assert r["ttlMs"] == 0
      assert r["cacheScope"] == "private"

      assert %{"name" => name, "version" => version} =
               r["_meta"]["io.modelcontextprotocol/serverInfo"]

      assert is_binary(name) and is_binary(version)
      refute Map.has_key?(r, "serverInfo"), "serverInfo left the body in spec PR #3002"
      refute Map.has_key?(r, "protocolVersions"), "the field is supportedVersions"
    end

    test "supported_versions: narrows what discover advertises and what -32022 lists, and is refused by name when malformed" do
      state =
        Server.new(
          catalog: Catalog,
          dispatch: fn _n, a, _o -> {:ok, a} end,
          supported_versions: [@modern]
        )

      {_, r} =
        Server.handle_message(state, %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "server/discover"
        })

      assert r["result"]["supportedVersions"] == [@modern]

      {_, e} =
        Server.handle_message(
          state,
          modern("tools/list", %{
            "_meta" => %{"io.modelcontextprotocol/protocolVersion" => @legacy}
          })
        )

      assert e["error"]["code"] == -32_022
      assert e["error"]["data"] == %{"supported" => [@modern], "requested" => @legacy}

      for bad <- [[], ["1900-01-01"], [@modern, "x"], @modern] do
        assert_raise ArgumentError, ~r/supported_versions/, fn ->
          Server.new(catalog: Catalog, supported_versions: bad)
        end
      end
    end
  end

  describe "where _meta lives: params._meta, the schema's one position" do
    # JSONRPCRequest has no _meta; RequestParams requires one with protocolVersion and
    # clientCapabilities (2026-07-28). The package read the message's top level until 0.5.0
    # and its own tests sent it there -- so a spec-following stdio client got a
    # legacy-shaped result while the server advertised modern.
    @spec_meta %{
      "io.modelcontextprotocol/protocolVersion" => @modern,
      "io.modelcontextprotocol/clientCapabilities" => %{}
    }

    test "a request carrying params._meta is served as modern" do
      r =
        send_msg(%{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "tools/list",
          "params" => %{"_meta" => @spec_meta}
        })

      assert r["result"]["resultType"] == "complete"
      assert r["result"]["_meta"]["io.modelcontextprotocol/serverInfo"]["name"]
    end

    test "a top-level _meta is refused by name, whether or not params._meta is there too" do
      for extra <- [%{}, %{"params" => %{"_meta" => @spec_meta}}] do
        msg =
          Map.merge(
            %{"jsonrpc" => "2.0", "id" => 7, "method" => "tools/list", "_meta" => @spec_meta},
            extra
          )

        r = send_msg(msg)
        assert r["error"]["code"] == -32_602
        assert r["error"]["message"] =~ "params._meta"
        assert r["id"] == 7
      end
    end

    test "params._meta lacking a required field is refused by name" do
      for {drop, field} <- [
            {"io.modelcontextprotocol/protocolVersion", "protocolVersion"},
            {"io.modelcontextprotocol/clientCapabilities", "clientCapabilities"}
          ] do
        meta = Map.delete(@spec_meta, drop)

        r =
          send_msg(%{
            "jsonrpc" => "2.0",
            "id" => 8,
            "method" => "tools/list",
            "params" => %{"_meta" => meta}
          })

        assert r["error"]["code"] == -32_602, "missing #{field}"
        assert r["error"]["message"] =~ field
      end
    end

    test "on stdio a bare server/discover is still the era probe, and its result is full" do
      r = send_msg(%{"jsonrpc" => "2.0", "id" => 9, "method" => "server/discover"})
      assert r["result"]["supportedVersions"] == [@modern, @legacy]
      assert r["result"]["resultType"] == "complete"
    end

    test "a legacy request declared through params._meta is served as legacy" do
      meta = %{"io.modelcontextprotocol/protocolVersion" => @legacy}

      r =
        send_msg(%{
          "jsonrpc" => "2.0",
          "id" => 10,
          "method" => "ping",
          "params" => %{"_meta" => meta}
        })

      assert r["result"] == %{}
      refute r["result"]["resultType"]
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

    test "a ping declaring 2025-11-25 through _meta is answered" do
      r = send_msg(legacy_meta("ping"))

      assert r["result"] == %{},
             "ping exists in 2025-11-25. This server advertises 2025-11-25 in " <>
               "server/discover and lists it in the -32022 `supported` payload, and the " <>
               "specification tells a client to pick from that list and retry the request " <>
               "— which produces this message. Refusing it refuses a revision we advertise."
    end
  end

  describe "state threads through both era branches" do
    test "shutdown declaring 2025-11-25 through _meta still sets shutdown?" do
      assert Server.shutdown?(send_for_state(legacy_meta("shutdown"))),
             "the legacy branch returns the recursion's tuple whole; if it returned the " <>
               "pre-recursion state instead, the transport would never stop"
    end

    test "shutdown declaring 2026-07-28 through _meta still sets shutdown?" do
      assert Server.shutdown?(send_for_state(modern("shutdown")))
    end

    test "a ping at either revision leaves the state alone" do
      refute Server.shutdown?(send_for_state(legacy_meta("ping")))
      refute Server.shutdown?(send_for_state(modern("ping")))
    end
  end

  describe "the result envelope follows the declared revision, not the carrier" do
    test "a 2026-07-28 result carries resultType and serverInfo _meta" do
      r = send_msg(modern("tools/list"))

      assert r["result"]["resultType"] == "complete"
      assert r["result"]["_meta"]["io.modelcontextprotocol/serverInfo"]
    end

    test "a result for a request declaring 2025-11-25 carries neither" do
      r = send_msg(legacy_meta("tools/list"))

      assert r["result"]["tools"], "the request is still served"

      refute r["result"]["resultType"],
             "resultType was added in 2026-07-28; the spec says clients MUST treat results " <>
               "from earlier-protocol servers that omit it as \"complete\", so emitting it " <>
               "on a 2025-11-25 result claims a revision the client did not ask for"

      refute r["result"]["_meta"],
             "the serverInfo _meta key is a 2026-07-28 addition and does not belong on a " <>
               "result answering a request that declared 2025-11-25"
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
