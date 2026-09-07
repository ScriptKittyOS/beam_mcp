# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Transport.HTTPBanditTest do
  @moduledoc """
  The transport against a REAL LISTENER, on a real socket, with real pipelining.

  Everything else in this suite drives `call/2` through `Plug.Test`, which builds a conn from an
  in-memory binary: there is no connection, so there is nothing that can be left in a state the
  next request inherits, and `read_body/2` is a `:binary.part` that can neither block nor fail.
  Two gaps in `slices/002-streamable-http/FINDINGS.md` are recorded there as not closable
  without this instrument. This file stands it up and closes the one the owner scoped in.

  WHAT IS ACTUALLY WRONG, measured on this tree rather than carried over. A refusal issued
  before `read_body_bounded/1` answers on a conn whose request body has not been read. Bandit
  then runs `ensure_completed/1` (`deps/bandit/lib/bandit/http1/socket.ex:578`) and DRAINS that
  body on the server's behalf -- up to the 8_000_000-byte cap in
  `do_read_content_length_data!/4` (:249), waiting up to its 15_000 ms read timeout (:251).
  So the server reads a body it has already decided not to read, for a caller it has already
  refused, on a path `authorize/1` may leave unauthenticated. Above the cap the drain fails and
  the connection is dropped with nothing said to the client.

  Both halves are measured in `slices/003-release-0-3-1/logs/probe-d-bandit-drain-limits.txt`:

      authorize 403, 9000160-byte body            responses=1  socket=closed
        ...with  ** (Bandit.HTTPError) Unable to read remaining data in request body
      authorize 403, declares +5MB, sends 160     responses=1  socket=open
      200, two pipelined                          responses=2  socket=open

  A response header of `connection: close` is what declines the drain: Bandit's
  `handle_keepalive/3` (:487-500) reads it, sets `keepalive: false`, and
  `ensure_completed(%{keepalive: false})` returns without reading anything (:579). So this is
  pinned BY EFFECT -- the socket state the server leaves the client in -- and not by the
  presence of a header string.

  A CORRECTION TO THE FINDING THIS WORK CAME FROM, recorded rather than quietly worked around.
  Slice 002 lane s3 measured `second-request-answered=False` for a pre-read refusal. On
  bandit 1.12.5 / thousand_island 1.5.0 that does NOT reproduce at ordinary body sizes: the
  drain succeeds and the second pipelined request IS answered
  (`logs/probe-d-bandit-drain.txt`, three body sizes up to 1 MB, all `responses=2`). The defect
  is real; the symptom named for it was not the one this adapter shows.

  `async: false` on purpose -- these bind a listening socket and read raw bytes off it.
  """
  use ExUnit.Case, async: false

  alias BeamMCP.Transport.HTTP

  @modern "2026-07-28"
  @vkey "io.modelcontextprotocol/protocolVersion"

  # Enough over bandit's 8_000_000-byte drain cap that the drain cannot complete.
  @over_drain_cap 9_000_000
  # Declared but never sent, so the drain blocks on a client that will not finish. The bytes
  # are never written, so this is cheap.
  @declared_but_unsent 5_000_000

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
          input_schema: %{"type" => "object", "properties" => %{}, "additionalProperties" => true}
        }
      ]
    end
  end

  # -- the listener -------------------------------------------------------------------------

  defp listen(extra) do
    plug_opts =
      Keyword.merge(
        [
          tool_catalog: Catalog,
          dispatch: fn _n, a, _o -> {:ok, a} end,
          authorize: fn _conn -> :ok end,
          allowed_origins: :any
        ],
        extra
      )

    spec =
      Supervisor.child_spec(
        {Bandit, plug: {HTTP, plug_opts}, port: 0, ip: :loopback, startup_log: false},
        id: {Bandit, make_ref()}
      )

    pid = start_supervised!(spec)
    {:ok, {_address, port}} = ThousandIsland.listener_info(pid)
    port
  end

  # ONE connection, everything written in ONE send, which is what pipelining is. Writing the
  # second request only after reading the first response would test nothing: the point is that
  # its bytes are already on the wire when the server decides what to do with the connection.
  #
  # Returns the bytes AND whether the server closed the connection or left it open, because
  # the socket state is the effect this file exists to measure.
  defp exchange(port, bytes_to_send) do
    {:ok, sock} =
      :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false, packet: :raw], 5_000)

    # The send result is not asserted: a server that answers and closes while a large body is
    # still being written makes `{:error, :closed}` here a correct outcome, not a failure.
    # What the test reads is what came back.
    _ = :gen_tcp.send(sock, bytes_to_send)
    result = drain(sock, "")
    :gen_tcp.close(sock)
    result
  end

  # `:closed` means the server ended the connection. `:open` means it is still holding it --
  # which, for a refused request with an unfinished body, means it is still draining.
  defp drain(sock, acc) do
    case :gen_tcp.recv(sock, 0, 700) do
      {:ok, data} -> drain(sock, acc <> data)
      {:error, :timeout} -> {acc, :open}
      {:error, :closed} -> {acc, :closed}
    end
  end

  defp responses(bytes), do: length(String.split(bytes, "HTTP/1.1 ")) - 1

  defp closes?(bytes), do: bytes |> String.downcase() |> String.contains?("connection: close")

  # `declared` is the Content-Length the request announces; `body` is what is actually written.
  # Passing a `declared` larger than the body is how a slow or truncated client is simulated
  # without writing megabytes.
  defp req(method, body, opts \\ []) do
    declared = Keyword.get(opts, :declared, byte_size(body))
    extra = Keyword.get(opts, :headers, [])
    header_lines = Enum.map_join(extra, "", fn {k, v} -> "#{k}: #{v}\r\n" end)

    "#{method} /mcp HTTP/1.1\r\n" <>
      "host: localhost\r\n" <>
      "content-type: application/json\r\n" <>
      "content-length: #{declared}\r\n" <>
      "mcp-protocol-version: #{@modern}\r\n" <>
      "mcp-method: tools/call\r\n" <>
      "mcp-name: echo\r\n" <> header_lines <> "\r\n" <> body
  end

  defp call_json(id, pad \\ 0) do
    Jason.encode!(%{
      "jsonrpc" => "2.0",
      "id" => id,
      "method" => "tools/call",
      "params" => %{"name" => "echo", "arguments" => %{}},
      "_meta" => %{@vkey => @modern},
      "pad" => String.duplicate("x", pad)
    })
  end

  defp good_post(id), do: req("POST", call_json(id))

  # An unfinished body on a request that will be refused before the body read. The bytes are
  # never sent, so the server is left draining a client that will not finish.
  defp unfinished(method, headers \\ []) do
    body = call_json(1)
    req(method, body, declared: byte_size(body) + @declared_but_unsent, headers: headers)
  end

  # -- the controls, which are what make the rest mean anything ------------------------------

  describe "a live listener: what a refusal does to the connection" do
    test "an ordinary 200 keeps the connection and answers the pipelined second request" do
      # THE FIRST CONTROL. Without it every assertion below is satisfied by a server that
      # closes on everything, which is a different bug wearing the fix's clothes.
      port = listen([])

      {bytes, state} = exchange(port, good_post(1) <> good_post(2))

      assert responses(bytes) == 2
      assert state == :open
      refute closes?(bytes)
      assert String.contains?(bytes, "\"id\":1")
      assert String.contains?(bytes, "\"id\":2")
    end

    test "a refusal AFTER the body has been read keeps the connection" do
      # THE SECOND CONTROL, and the one that pins the SPLIT rather than the behaviour on
      # either side of it. A parse error is a refusal like any other, but the body is already
      # read by the time it is issued, so there is nothing left on the wire and no reason to
      # end the connection. If `connection: close` were applied to every refusal instead of to
      # the ones in front of the body read, this is the test that fails.
      port = listen([])

      bad_json = "{not json"

      {bytes, state} = exchange(port, req("POST", bad_json) <> good_post(2))

      assert String.contains?(bytes, "HTTP/1.1 400")
      assert responses(bytes) == 2
      assert state == :open
      refute closes?(bytes)
    end

    # THE POPULATION IS DERIVED, NOT LISTED, per CONVENTIONS.md's "every place a mechanism
    # reads the same kind of input is one mechanism". The set is the steps of `before_body/2`
    # in `lib/beam_mcp/transport/http.ex`, and it was derived with:
    #
    #     $ grep -n '{:refused,' lib/beam_mcp/transport/http.ex
    #     $ grep -n '<- check_origin\|<- check_method\|<- authorize\|<- read_body_bounded' \
    #         lib/beam_mcp/transport/http.ex
    #
    # The first lists every refusal site; the second says which `with` step each belongs to and
    # where the body read sits among them. SIX sites are at or before the read -- the Origin
    # 403, the 405, `authorize/1`'s 500, its 403 and its contract-violation 403, and
    # `read_body_bounded/1`'s own 400 -- of which only the 413 already closed. The brief this
    # work came from named three; the derivation found six, which is the whole argument for
    # deriving.
    #
    # A case per STEP, with the sites named, because a step is what a future change adds -- and
    # a step added to `before_body/2` inherits the behaviour without needing a new finding.

    test "an Origin refusal ends the connection instead of draining the body it refused" do
      port = listen(allowed_origins: ["https://good.example"])

      {bytes, state} =
        exchange(port, unfinished("POST", [{"origin", "https://evil.example"}]))

      assert String.contains?(bytes, "HTTP/1.1 403")
      assert closes?(bytes)
      # THE EFFECT, which is what makes this an anchor rather than a string check: the server
      # ends the connection instead of reading megabytes for a caller it just refused. Without
      # the header Bandit keeps the connection and drains, and this reads `:open`.
      assert state == :closed
    end

    test "an authorize refusal ends the connection instead of draining the body it refused" do
      port = listen(authorize: fn _conn -> {:error, :nope} end)

      {bytes, state} = exchange(port, unfinished("POST"))

      assert String.contains?(bytes, "HTTP/1.1 403")
      assert closes?(bytes)
      assert state == :closed
    end

    test "an authorize that raises ends the connection instead of draining the body" do
      # The 500 limb: a different `{:refused, ...}` site in the same step, and the limb slice
      # 002's lane s3 probed.
      port = listen(authorize: fn _conn -> raise "authorize exploded" end)

      {bytes, state} = exchange(port, unfinished("POST"))

      assert String.contains?(bytes, "HTTP/1.1 500")
      assert closes?(bytes)
      assert state == :closed
    end

    test "an authorize breaking its contract ends the connection instead of draining" do
      # The third `{:refused, ...}` site in the same step: a host returning neither `:ok` nor
      # `{:error, reason}` is failed closed with a 403. Named separately because "the authorize
      # 403" reads like one site and is two.
      port = listen(authorize: fn _conn -> :yes_please end)

      {bytes, state} = exchange(port, unfinished("POST"))

      assert String.contains?(bytes, "HTTP/1.1 403")
      assert closes?(bytes)
      assert state == :closed
    end

    test "a 405 ends the connection instead of draining the body it refused" do
      # A PUT WITH A BODY, not a GET. A GET leaves nothing unread, so it would pass whether or
      # not the header is sent and would pin nothing. The method check refuses every non-POST,
      # and a non-POST is free to carry a body.
      port = listen([])

      {bytes, state} = exchange(port, unfinished("PUT"))

      assert String.contains?(bytes, "HTTP/1.1 405")
      assert String.downcase(bytes) =~ "allow: post"
      assert closes?(bytes)
      assert state == :closed
    end

    test "a refusal over the adapter's drain cap now announces the close it always did" do
      # THE CASE WHERE THE CLIENT WAS TOLD NOTHING. Above bandit's 8_000_000-byte drain cap the
      # drain fails, the adapter logs `Unable to read remaining data in request body` and drops
      # the connection -- pipelined request lost, no `connection: close` in the response that
      # preceded it. Measured before the fix in `logs/probe-d-bandit-drain-limits.txt`:
      #
      #     authorize 403, 9000160-byte body   responses=1  socket=closed
      #
      # The connection ended either way. What changes is that the client is now told.
      port = listen(authorize: fn _conn -> {:error, :nope} end)

      big = call_json(1, @over_drain_cap)

      {bytes, state} = exchange(port, req("POST", big) <> good_post(2))

      assert String.contains?(bytes, "HTTP/1.1 403")
      assert closes?(bytes)
      assert state == :closed
      # Stated so nobody reads a promise into the fix: the second request is still not
      # answered, and it cannot be. Reading the body of a caller already refused is the thing
      # being declined.
      assert responses(bytes) == 1
    end

    test "an oversized body still ends the connection and says so" do
      # The 413 is the site that was already correct, and it is pinned here rather than
      # assumed: it moved from its own `close_after/1` call to the one path all six now share,
      # and a refactor that drops a behaviour while centralising it is exactly the shape this
      # repository keeps finding. Over @max_body_bytes (1_048_576) but under the adapter's
      # drain cap, so this is the transport's own refusal and not the adapter's.
      port = listen([])

      big = call_json(1, 1_100_000)

      {bytes, state} = exchange(port, req("POST", big) <> good_post(2))

      assert String.contains?(bytes, "HTTP/1.1 413")
      assert closes?(bytes)
      assert state == :closed
    end
  end
end
