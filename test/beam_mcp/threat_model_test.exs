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

  alias BeamMCP.Transport.{HTTP, Stdio}

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
      [first, second] = drive_stdio(deep <> "\n" <> ping <> "\n") |> lines()
      assert %{"error" => %{"code" => -32_600, "message" => message}} = first
      assert message =~ "nests deeper than #{max} levels"
      assert second["id"] == 2
    end

    test "brackets inside a string are text, escaped quotes do not end the string, and siblings do not add up" do
      max = BeamMCP.JSON.max_depth()
      # Two hundred brackets inside a string value: depth one.
      inside = ~s({"k":"#{String.duplicate("[", max * 3)}"})
      assert {:ok, %{"k" => _}} = BeamMCP.JSON.decode(inside)
      # An escaped quote inside the string, then brackets: still inside the string.
      escaped = ~s({"k":"a\\"#{String.duplicate("[", max * 3)}"})
      assert {:ok, %{"k" => _}} = BeamMCP.JSON.decode(escaped)
      # A backslash before a bracket inside a string, as JSON allows only for a few escapes:
      # Jason refuses it, and that is Jason's answer, not a nesting refusal.
      assert {:error, %Jason.DecodeError{}} =
               BeamMCP.JSON.decode(~s({"k":"\\[#{String.duplicate("[", max * 3)}"}))

      # Many siblings at depth two: the closing bracket counts back down.
      siblings = "[" <> Enum.map_join(1..(max * 3), ",", fn _ -> "[]" end) <> "]"
      assert {:ok, list} = BeamMCP.JSON.decode(siblings)
      assert length(list) == max * 3
      # Exactly the bound, then one past it, on bare arrays.
      assert {:ok, _} =
               BeamMCP.JSON.decode(String.duplicate("[", max) <> String.duplicate("]", max))

      assert {:error, {:nesting, depth, ^max}} =
               BeamMCP.JSON.decode(
                 String.duplicate("[", max + 1) <> String.duplicate("]", max + 1)
               )

      assert depth == max + 1
      # Objects count the same as arrays.
      assert {:error, {:nesting, _, ^max}} =
               BeamMCP.JSON.decode(
                 String.duplicate(~s({"a":), max + 1) <> "1" <> String.duplicate("}", max + 1)
               )
    end

    test "the bound is one number, read from one place, and it is the number the page states" do
      max = BeamMCP.JSON.max_depth()
      assert is_integer(max) and max > 0
      assert page() =~ "nests deeper than #{max} levels"
      assert page() =~ "past **#{max} levels**"
    end

    test "the number is sixty-four, pinned by bytes and not by the constant it pins" do
      # A review lane moved @max_depth to 8 and the suite stayed green: every other test here
      # is written relative to max_depth/0. This one is not.
      assert {:ok, _} =
               BeamMCP.JSON.decode(String.duplicate("[", 64) <> String.duplicate("]", 64))

      assert {:error, {:nesting, 65, 64}} =
               BeamMCP.JSON.decode(String.duplicate("[", 65) <> String.duplicate("]", 65))
    end
  end

  describe "duplicate keys are refused, not resolved" do
    # Jason keeps the first of two equal keys; most other parsers keep the last. A hop in front
    # of this server that routes on the last "name" while this server executes the first is
    # the two-sources-of-truth the header check exists to close, reopened inside the body.
    @dup ~s({"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"strict","name":"echo",) <>
           ~s("arguments":{},"_meta":{"io.modelcontextprotocol/protocolVersion":"#{@modern}",) <>
           ~s("io.modelcontextprotocol/clientCapabilities":{}}}})

    test "over HTTP a body with a repeated key is -32600 and 400, naming the key" do
      conn = post(@dup, "tools/call")
      assert conn.status == 400
      %{"error" => %{"code" => -32_600, "message" => message}} = Jason.decode!(conn.resp_body)
      assert message =~ ~s(duplicate key "name")
    end

    test "over stdio a line with a repeated key is -32600 naming the key, and the loop keeps going" do
      ping = ~s({"jsonrpc":"2.0","id":2,"method":"ping"})
      [first, second] = drive_stdio(@dup <> "\n" <> ping <> "\n") |> lines()
      assert %{"error" => %{"code" => -32_600, "message" => message}} = first
      assert message =~ ~s(duplicate key "name")
      assert second["id"] == 2
    end

    test "the decoder names the first repeated key at any depth, and admits equal keys in different objects" do
      assert {:error, {:duplicate_key, "a"}} = BeamMCP.JSON.decode(~s({"x":{"a":1,"b":2,"a":3}}))

      assert {:ok, %{"x" => %{"a" => 1}, "y" => %{"a" => 2}}} =
               BeamMCP.JSON.decode(~s({"x":{"a":1},"y":{"a":2}}))

      assert {:ok, [%{"a" => 1}, %{"a" => 2}]} = BeamMCP.JSON.decode(~s([{"a":1},{"a":2}]))
      # Inside an array element, at any depth of arrays: a mutant that handed lists back as
      # decoded admitted this one.
      assert {:error, {:duplicate_key, "a"}} = BeamMCP.JSON.decode(~s({"x":[1,[{"a":1,"a":2}]]}))
      # A key is compared after unescaping, as every decoder compares it: "\u0061" is "a".
      # That is why the repeat is found in the decoded objects and not in the bytes.
      assert {:error, {:duplicate_key, "a"}} = BeamMCP.JSON.decode(~s({"a":1,"\\u0061":2}))
    end
  end

  describe "the stdio loop under a hostile line or a host fault" do
    test "a host dispatch that raises, throws or exits is answered -32603 with the id, and the loop keeps going" do
      faults = [fn -> raise "boom SECRET=1" end, fn -> throw(:x) end, fn -> exit(:y) end]

      for fault <- faults do
        call =
          ~s({"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"echo","arguments":{}}})

        ping = ~s({"jsonrpc":"2.0","id":8,"method":"ping"})

        [first, second] =
          drive_stdio(call <> "\n" <> ping <> "\n", fn _n, _a, _o -> fault.() end) |> lines()

        assert %{"id" => 7, "error" => %{"code" => -32_603, "message" => message}} = first
        refute message =~ "SECRET"
        refute inspect(first) =~ "SECRET"
        assert second["id"] == 8
      end
    end

    test "a line that is JSON but not an object is -32600 naming the type, never silence" do
      for {line, type} <- [
            {~s("x"), "a string"},
            {"42", "a number"},
            {"null", "null"},
            {"true", "a scalar"}
          ] do
        ping = ~s({"jsonrpc":"2.0","id":2,"method":"ping"})
        [first, second] = drive_stdio(line <> "\n" <> ping <> "\n") |> lines()
        assert %{"error" => %{"code" => -32_600, "message" => message}} = first
        assert message == "Expected a JSON object, got #{type}"
        assert second["id"] == 2
      end
    end

    test "a parse error carries no inspected term and none of the client's bytes" do
      [first] = drive_stdio("{not json SECRET=2\n") |> lines()

      assert %{
               "error" =>
                 %{"code" => -32_700, "message" => "Parse error: body is not valid JSON"} = err
             } = first

      refute Map.has_key?(err, "data")
      refute inspect(first) =~ "SECRET"
    end

    test "a line past the frame bound is refused once, its tail discarded to the newline, and the next line answered" do
      long = String.duplicate("x", 1_048_577) <> " SECRET=3"
      ping = ~s({"jsonrpc":"2.0","id":2,"method":"ping"})
      [first, second] = drive_stdio(long <> "\n" <> ping <> "\n") |> lines()

      assert %{
               "error" => %{
                 "code" => -32_600,
                 "message" => "Request line exceeds 1048576 bytes"
               }
             } = first

      refute inspect(first) =~ "SECRET"
      assert second["id"] == 2
    end
  end

  describe "the page and the tree" do
    test "every test the page cites exists, by path and by name" do
      cited = BeamMCP.Boundary.citations(page())

      assert length(cited) >= 6,
             "the page cites #{length(cited)} tests; it names a refusal per vector"

      assert BeamMCP.Boundary.citation_defects(page(), @root) == []
    end

    test "every REFUSED or BOUNDED row of the wire table cites at least one test, read row by row" do
      # A consumer-parse-back lane found a row whose citations the reader returned as none: the
      # prose column carried escaped quotes, and the pairing of quotes shifted across the
      # backtick path. A row that vanishes from the population is caught here, per row.
      rows =
        page()
        |> String.split("\n")
        |> Enum.filter(&wire_row?/1)

      assert length(rows) >= 10

      for row <- rows do
        [_, vector | _] = String.split(row, "|")

        assert BeamMCP.Boundary.citations(row) != [],
               "the row #{String.trim(vector)} cites no test the reader can see"
      end
    end

    test "the reader sees a citation beside escaped quotes in the prose, and asks ExUnit which cited tests are live" do
      row =
        ~s(| **x** | REFUSED | says `"name"` and \\"quoted\\" | ) <>
          ~s(`test/beam_mcp/threat_model_test.exs` "a name" "another" | — |)

      assert BeamMCP.Boundary.citations(row) ==
               [{"test/beam_mcp/threat_model_test.exs", ["a name", "another"]}]

      # Liveness is ExUnit's answer, read from the module's own test list and tags -- not a
      # text reader's: a review lane found five skip spellings a text reader called live and
      # ExUnit skipped, and a describetag is block-wide. The fixture modules register nothing
      # with the runner.
      dir =
        Path.join(System.tmp_dir!(), "beam_mcp_citation_#{System.unique_integer([:positive])}")

      File.mkdir_p!(Path.join(dir, "test"))

      File.write!(Path.join(dir, "test/a_test.exs"), """
      defmodule BeamMCP.CitationFixtureA do
        use ExUnit.Case, register: false

        # test "commented out" do
        @tag :skip
        test "skipped" do
        end

        @tag :skip
        @tag :other
        test "skipped then tagged" do
        end

        @tag skip: true
        test "skipped by keyword" do
        end

        @tag skip: "why"
        test "skipped with a reason" do
        end

        @tag :skip

        test "skipped across a blank line" do
        end

        @tag :skip
        # a comment inside the attribute run
        test "skipped past a comment" do
        end

        @tag skip: false
        test "not skipped after all" do
        end

        describe "a block" do
          @describetag :skip
          test "skipped by describetag" do
          end

          setup do
            :ok
          end

          test "skipped by describetag, later in the block" do
          end
        end

        test "live" do
        end
      end
      """)

      File.write!(Path.join(dir, "test/b_test.exs"), """
      defmodule BeamMCP.CitationFixtureB do
        use ExUnit.Case, register: false
        @moduletag :skip

        test "skipped by moduletag" do
        end
      end
      """)

      page =
        ~s(`test/a_test.exs` "commented out" "skipped" "skipped then tagged" "skipped by keyword" ) <>
          ~s("skipped with a reason" "skipped across a blank line" "skipped past a comment" ) <>
          ~s("not skipped after all" "skipped by describetag" ) <>
          ~s("skipped by describetag, later in the block" "live"; ) <>
          ~s(`test/b_test.exs` "skipped by moduletag")

      assert BeamMCP.Boundary.citation_defects(page, dir) == [
               ~s(test/a_test.exs names no live test "commented out"),
               ~s(test/a_test.exs names no live test "skipped"),
               ~s(test/a_test.exs names no live test "skipped then tagged"),
               ~s(test/a_test.exs names no live test "skipped by keyword"),
               ~s(test/a_test.exs names no live test "skipped with a reason"),
               ~s(test/a_test.exs names no live test "skipped across a blank line"),
               ~s(test/a_test.exs names no live test "skipped past a comment"),
               ~s(test/a_test.exs names no live test "skipped by describetag"),
               ~s(test/a_test.exs names no live test "skipped by describetag, later in the block"),
               ~s(test/b_test.exs names no live test "skipped by moduletag")
             ]

      File.rm_rf!(dir)
    end
  end

  describe "the stdio frame bounds at their edges" do
    test "a line of exactly 1 MiB is admitted, one byte more is refused, and the message says exceeds" do
      pad = fn n ->
        ~s({"jsonrpc":"2.0","id":2,"method":"ping","pad":") <> String.duplicate("x", n) <> ~s("})
      end

      base = byte_size(pad.(0))
      exact = pad.(1_048_576 - base)
      assert byte_size(exact) == 1_048_576
      [only] = drive_stdio(exact <> "\n") |> lines()
      assert only["id"] == 2
      [refused] = drive_stdio(pad.(1_048_577 - base) <> "\n") |> lines()
      assert refused["error"]["message"] == "Request line exceeds 1048576 bytes"
    end

    test "a header line of a legacy Content-Length block is bounded like any line, and refused by name past it" do
      long_header = "X-Lane: " <> String.duplicate("h", 4 * 1_048_576)
      ping = ~s({"jsonrpc":"2.0","id":2,"method":"ping"})

      input =
        "Content-Length: #{byte_size(ping)}\r\n#{long_header}\r\n\r\n" <> ping <> ping <> "\n"

      [first, second] = drive_stdio(input) |> lines()
      assert first["error"]["message"] == "Request line exceeds 1048576 bytes"
      assert second["id"] == 2
    end

    test "reading a line costs the loop about the line's bytes, not sixty times them" do
      # The reader once accumulated one-byte binaries in a list: ~40 B of heap per byte of
      # line, 46-67 MiB LIVE for a 1 MiB line (a review lane's measurement). A line is now
      # built as one off-heap binary. Measured while the line is being read, by a sampler --
      # what the loop retains after the read is nothing either way, so that is not the pin.
      pad = fn n ->
        ~s({"jsonrpc":"2.0","id":2,"method":"ping","pad":") <> String.duplicate("x", n) <> ~s("})
      end

      line = pad.(1_048_576 - byte_size(pad.(0)))
      parent = self()

      reader =
        spawn_link(fn ->
          receive do
            :go -> send(parent, {:done, drive_stdio(line <> "\n")})
          end
        end)

      sampler =
        spawn_link(fn ->
          send(reader, :go)
          send(parent, {:max_heap, sample_max_heap(reader, 0)})
        end)

      assert_receive {:done, output}, 60_000
      assert [%{"id" => 2}] = lines(output)
      assert_receive {:max_heap, max_bytes}, 5_000
      _ = sampler

      # 0 MiB sampled after the fix; the list design read 58, and a whole-line downcase in
      # the Content-Length check -- the sampler's first find -- 40.
      assert max_bytes < 8 * 1_048_576,
             "the loop's heap reached #{div(max_bytes, 1_048_576)} MiB while reading a 1 MiB line"
    end

    test "a size refusal is -32600 on stdio as it is over HTTP, so one vector has one code" do
      long = String.duplicate("x", 1_048_577)
      [first] = drive_stdio(long <> "\n") |> lines()
      assert first["error"]["code"] == -32_600
      input = "Content-Length: 1048577\r\n\r\n" <> String.duplicate("a", 1_048_577)
      [frame] = drive_stdio(input) |> lines()
      assert frame["error"]["code"] == -32_600
    end

    test "a legacy Content-Length frame over the cap is refused by name and its declared body is drained, never read as the next frames" do
      smuggled = ~s({"jsonrpc":"2.0","id":99,"method":"ping","smuggled":true})
      body = smuggled <> "\n" <> String.duplicate("a", 1_100_000) <> "\n"
      ping = ~s({"jsonrpc":"2.0","id":2,"method":"ping"})
      input = "Content-Length: #{byte_size(body)}\r\n\r\n" <> body <> ping <> "\n"
      [first, second] = drive_stdio(input) |> lines()
      assert first["error"]["message"] == "Request frame exceeds 1048576 bytes"
      assert second["id"] == 2
    end
  end

  defp page do
    path = Path.join(@root, @page)
    assert File.exists?(path), "#{@page} is not in the tree"
    File.read!(path)
  end

  # A row of the wire table whose posture column says REFUSED or BOUNDED (the trust table's
  # rows start the same way; their second column is not a posture).
  defp wire_row?(line) do
    case String.split(line, "|") do
      ["", " **" <> _, posture | _] -> posture =~ "REFUSED" or posture =~ "BOUNDED"
      _ -> false
    end
  end

  # The largest total_heap_size seen on `pid` while it lives, sampled every millisecond.
  defp sample_max_heap(pid, max) do
    case Process.info(pid, :total_heap_size) do
      {:total_heap_size, words} ->
        Process.sleep(1)
        sample_max_heap(pid, max(max, words * 8))

      nil ->
        max
    end
  end

  defp lines(output), do: output |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)

  # The stdio loop over a StringIO, as stdio_test does: the group leader is what
  # `IO.binread(:stdio, _)` resolves to.
  defp drive_stdio(input, dispatch \\ fn _n, a, _o -> {:ok, a} end) do
    {:ok, device} = StringIO.open(input, encoding: :latin1)
    original = Process.group_leader()
    Process.group_leader(self(), device)

    try do
      Stdio.run(catalog: Catalog, dispatch: dispatch)
    after
      Process.group_leader(self(), original)
    end

    {:ok, {_input, output}} = StringIO.close(device)
    output
  end
end
