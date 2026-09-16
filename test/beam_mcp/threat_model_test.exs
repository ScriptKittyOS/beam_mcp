# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.ThreatModelTest do
  @moduledoc """
  The wire bounds `docs/threat-model.md` states as refusals, driven with bytes, and the page's
  citations held to the tree.

  Two bounds are this package's own on every transport: a body over 1 MiB, and JSON nesting
  past `BeamMCP.JSON.max_depth/0`. The first was pinned before this page existed
  (`test/beam_mcp/transport/http_test.exs` "a body over the cap is refused with 413 and the
  connection closes"; `test/beam_mcp/transport/stdio_test.exs` "a line beyond the frame bound
  is refused rather than buffered"). The second is pinned here, red first: before it, a 1 MiB
  body nested 524 288 levels deep was decoded in full -- 79-96 ms and a 38 MiB heap for one
  request, ~36x the body -- and refused only afterwards by shape. The size cap bounded the
  depth; it did not bound the cost. Now the depth is read before a byte is decoded, in one
  place both transports call.

  The page cites tests by path and name for every refusal it claims; that census is the same
  one `docs/will-not-implement.md` is held by.
  """
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias BeamMCP.Transport.HTTP

  @root Path.expand("../..", __DIR__)
  @page "docs/threat-model.md"
  @hdr "mcp-protocol-version"
  @modern "2026-07-28"

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
            description: "Echo.",
            input_schema: %{"type" => "object"}
          }
        ],
        resources: [],
        prompts: []
      }
    end
  end

  defp opts do
    HTTP.init(
      catalog: Catalog,
      dispatch: fn _n, a, _o -> {:ok, a} end,
      authorize: fn _conn -> :ok end,
      allowed_origins: :any
    )
  end

  defp post(body, method) do
    :post
    |> conn("/mcp", body)
    |> put_req_header("content-type", "application/json")
    |> put_req_header(@hdr, @modern)
    |> put_req_header("mcp-method", method)
    |> put_req_header("mcp-name", "echo")
    |> HTTP.call(opts())
  end

  # A tools/call whose arguments nest `depth` levels below the message's own three
  # (message > params > arguments).
  defp nested_call(depth) do
    nest = String.duplicate("[", depth) <> String.duplicate("]", depth)

    ~s({"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"echo",) <>
      ~s("arguments":{"k":#{nest}},"_meta":{"io.modelcontextprotocol/protocolVersion":"#{@modern}",) <>
      ~s("io.modelcontextprotocol/clientCapabilities":{}}}})
  end

  describe "JSON nesting is bounded before the decoder runs" do
    test "over HTTP a body nested past the bound is refused by name, -32600 and 400, with the connection kept" do
      max = BeamMCP.JSON.max_depth()
      conn = post(nested_call(max), "tools/call")
      assert conn.status == 400
      %{"error" => %{"code" => -32_600, "message" => message}} = Jason.decode!(conn.resp_body)
      assert message =~ "nests deeper than #{max} levels"
      # The body was read in full (it is under the size cap), so there is nothing to drain.
      assert get_resp_header(conn, "connection") == []
    end

    test "over HTTP a body nested exactly to the bound is not refused for its depth" do
      max = BeamMCP.JSON.max_depth()
      # message > params > arguments > "k" is three levels of object before the arrays.
      conn = post(nested_call(max - 3), "tools/call")
      refute conn.resp_body =~ "nests deeper"
      assert conn.status == 200
    end

    test "the worst body under the size cap is refused with a heap that never held the nest" do
      max = BeamMCP.JSON.max_depth()
      body = String.duplicate("[", 524_288) <> String.duplicate("]", 524_288)
      assert byte_size(body) == 1_048_576
      parent = self()

      spawn_link(fn ->
        conn = post(body, "tools/call")
        {:total_heap_size, words} = Process.info(self(), :total_heap_size)
        send(parent, {:done, conn.status, conn.resp_body, words * 8})
      end)

      assert_receive {:done, 400, resp, heap_bytes}, 30_000
      assert resp =~ "nests deeper than #{max} levels"
      # Decoding this body read a 38 MiB heap (measured before the bound); the scan reads the
      # bytes and builds nothing, so the process's heap stays under a few MiB.
      assert heap_bytes < 8 * 1_048_576,
             "the handling process's heap reached #{div(heap_bytes, 1_048_576)} MiB"
    end

    test "over stdio a line nested past the bound is refused by name, and the loop keeps going" do
      max = BeamMCP.JSON.max_depth()
      deep = String.duplicate("[", max + 1) <> String.duplicate("]", max + 1)
      ping = ~s({"jsonrpc":"2.0","id":2,"method":"ping"})
      output = drive_stdio(deep <> "\n" <> ping <> "\n")
      [first, second] = output |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)
      assert %{"error" => %{"code" => -32_600, "message" => message}} = first
      assert message =~ "nests deeper than #{max} levels"
      assert second["id"] == 2
    end

    test "the bound is one number, read from one place, and it is the number the page states" do
      max = BeamMCP.JSON.max_depth()
      assert is_integer(max) and max > 0
      assert page() =~ "#{max} levels"
    end
  end

  describe "the page and the tree" do
    test "every test the page cites exists, by path and by name" do
      cited = BeamMCP.Boundary.citations(page())

      assert length(cited) >= 6,
             "the page cites #{length(cited)} tests; it names a refusal per vector"

      assert BeamMCP.Boundary.missing_citations(page(), @root) == []
    end
  end

  defp page do
    path = Path.join(@root, @page)
    assert File.exists?(path), "#{@page} is not in the tree"
    File.read!(path)
  end

  # The stdio loop over a StringIO, as stdio_test does: the group leader is what
  # `IO.binread(:stdio, _)` resolves to.
  defp drive_stdio(input) do
    {:ok, device} = StringIO.open(input, encoding: :latin1)
    original = Process.group_leader()
    Process.group_leader(self(), device)

    try do
      BeamMCP.Transport.Stdio.run(catalog: Catalog, dispatch: fn _n, a, _o -> {:ok, a} end)
    after
      Process.group_leader(self(), original)
    end

    {:ok, {_input, output}} = StringIO.close(device)
    output
  end
end
