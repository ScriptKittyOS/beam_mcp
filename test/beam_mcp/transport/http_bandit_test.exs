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
  (`slices/003-release-0-3-1/logs/probe-d-bandit-drain.txt`, three body sizes up to 1 MB,
  all `responses=2`). The defect
  is real; the symptom named for it was not the one this adapter shows.

  `async: false` on purpose -- these bind a listening socket and read raw bytes off it.
  """
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

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
  # `expect` is how many complete HTTP responses this exchange is waiting for. It is what the
  # read terminates on, and it is not a guess: every response this adapter sends carries a
  # `content-length`, so "complete" is decidable from the bytes rather than from a clock.
  #
  # Returns the bytes AND whether the server closed the connection or left it open, because
  # the socket state is the effect this file exists to measure.
  #
  # ------------------------------------------------------------------------------------------
  # WHY THE SOCKET IS `active: true` AND THE WRITE RUNS IN ITS OWN PROCESS. This is the fix, and
  # it is not a timeout change. Measured, not reasoned about.
  #
  # The 9 MB case: the server refuses on the headers, writes a 297-byte 403, and closes with
  # ~9 MB still unread, so the peer sends an RST. What that RST destroys is the question.
  #
  # `slices/006-harness-honesty/logs/probe-drain-mechanism.txt`, 40 runs per variant, reporting
  # `{bytes received, recv reason, send result, saw the 403?}`:
  #
  #     A  send everything, then read (what this file did)   29x {297, :closed, :ok, true}
  #                                                          11x {0, :closed, :ok, false}
  #     B  A, plus show_econnreset: true                     21x {297, :closed, ...}
  #                                                          11x {297, :econnreset, ...}
  #                                                           8x {0, :econnreset, :ok, false}
  #     C  passive recv concurrent with the write            40x {297, :closed, :ok, true}
  #     D  C, plus show_econnreset: true                     25x {297, :econnreset, ...}
  #                                                          15x {297, :closed, ...}
  #
  # So the bytes are LOST, not late: 11 of 40 reads saw ZERO bytes and reported the connection
  # ended. No timeout branch is taken and no buffer is partial, which is why slice 003's repair
  # -- one 700 ms window split into 10_000 + 700 -- reduced the rate and left the mechanism.
  # `show_econnreset: true` only renames the error (B); it does not save the data.
  #
  # Reading concurrently with the write (C, D) lost nothing in 80 idle runs. It was NOT enough:
  # `slices/006-harness-honesty/logs/probe-rate-mc8-load32-passive.txt` is 40 suites at `--max-cases 8` with 32 busy loops
  # alongside, and 6 of them still ended with `0 complete response(s)` and `0 byte(s) read`. A
  # PASSIVE socket keeps received bytes inside the port, and a failing `gen_tcp:send` destroys
  # the port -- so a reader that has not yet been SCHEDULED to call `recv` loses them, which is
  # exactly what CPU starvation produces.
  #
  # `active: true` moves them out of reach: the driver posts `{:tcp, sock, data}` into this
  # process's MAILBOX as the kernel delivers it, without this process running, and a message in
  # a mailbox cannot be taken back by a port dying. The driver also posts `{:tcp_error, sock,
  # :econnreset}` and `{:tcp_closed, sock}` AFTER the data it already read, and the mailbox is
  # FIFO, so "the connection ended" can never be observed before bytes that preceded it.
  #
  # `show_econnreset: true` is kept so that "the peer reset us" and "the peer closed cleanly"
  # are distinguishable in the message when a read does end early. Both mean the server ended
  # the connection, so both answer `:closed`.
  # ------------------------------------------------------------------------------------------
  # AND WHY A DESTROYED EXCHANGE IS REPEATED RATHER THAN REPORTED. `active: true` took the loss
  # from 11/40 to 3/60 and did not remove it, because the last of it is not on this side of the
  # wire at all.
  #
  # `slices/006-harness-honesty/logs/probe-loss-site.txt` separates the three places the 297 bytes could go. The plug's
  # `authorize` callback messages the test process, so "the server never answered" is
  # distinguishable from "the answer did not arrive". 60 runs under 32 busy loops:
  #
  #     57x  {297, :econnreset, ..., authorize ran: true}
  #      3x  {0,   :econnreset, ..., authorize ran: true}
  #
  # The server decided and wrote its refusal in 60 of 60. Three of those refusals never reached
  # the client. The server closes with ~9 MB unread, which makes Linux abort the connection with
  # an RST instead of a FIN, and an RST discards whatever of the response had not yet been
  # transmitted. `slices/006-harness-honesty/logs/probe-write-shape.txt` shows the write shape does not govern it either --
  # 120 runs in one 9 MB send lost 0, 120 runs in 64 KB chunks lost 5, on the same loaded machine.
  #
  # So the residue is a lost segment, and NO read logic can recover it. What the harness can do
  # is refuse to call it a measurement. `{0, :econnreset}` is not an observation of the server;
  # it is the absence of one. Reporting it as `{"", :closed}` was the old defect. Reporting it as
  # a failed `assert bytes =~ "HTTP/1.1 403"` is the SAME LIE WITH THE SIGN FLIPPED: a sentence
  # about the server, for bytes the server did send.
  #
  # An exchange that produced no measurement is therefore repeated on a fresh connection, and the
  # repeat is announced on stderr rather than hidden. This is not a retry of a failed assertion:
  # the predicate is protocol-determined -- the connection ended with fewer than `expect`
  # complete responses -- and it is decided before any assertion runs. A server that genuinely
  # never answers fails every attempt and raises, so nothing is masked; `slices/006-harness-honesty/logs/green-mutation-under-load.txt`
  # is the check that says so, with every killed mutant still scoring what the record scores.
  #
  # @attempts is derived from the measured loss: 5% at its worst leaves 5 attempts at 3e-7.
  @attempts 5
  @connect_ms 5_000
  @write_ms 15_000

  defp exchange(port, bytes_to_send, expect), do: exchange(port, bytes_to_send, expect, 1)

  defp exchange(port, bytes_to_send, expect, attempt) do
    {:ok, sock} =
      :gen_tcp.connect(
        ~c"127.0.0.1",
        port,
        [:binary, active: true, packet: :raw, show_econnreset: true],
        @connect_ms
      )

    # The send result is not asserted: a server that answers and closes while a large body is
    # still being written makes `{:error, :closed}` here a correct outcome, not a failure.
    # What the test reads is what came back.
    me = self()
    writer = spawn(fn -> send(me, {:written, self(), :gen_tcp.send(sock, bytes_to_send)}) end)

    result = collect(sock, "", expect)

    receive do
      {:written, ^writer, _} -> :ok
    after
      @write_ms -> :ok
    end

    :gen_tcp.close(sock)

    case result do
      {:aborted, reason, acc} when attempt < @attempts ->
        IO.puts(
          :stderr,
          "http_bandit_test: exchange #{attempt}/#{@attempts} produced no measurement " <>
            "(#{inspect(reason)} after #{complete_responses(acc)}/#{expect} complete " <>
            "responses, #{byte_size(acc)} bytes). Repeating on a fresh connection."
        )

        exchange(port, bytes_to_send, expect, attempt + 1)

      {:aborted, reason, acc} ->
        raise aborted(reason, acc, expect, attempt)

      {:unanswered, acc} ->
        raise unanswered(acc, expect)

      {bytes, state} ->
        {bytes, state}
    end
  end

  # THE READ TERMINATES ON THE PROTOCOL, NOT ON A SILENCE.
  #
  # `collect/3` reads until `expect` COMPLETE responses have been parsed out of the buffer --
  # status line, headers, and the `content-length` bytes that follow -- or until the server ends
  # the connection. A timeout here is never a verdict: it raises, because a harness that could
  # not finish reading has not measured anything, and neither has one whose bytes were destroyed
  # under it.
  #
  # WHAT THE PREVIOUS SHAPE GOT WRONG, and it is not the number. `drain/2` terminated on elapsed
  # silence in both directions: `{:error, :timeout} -> {acc, :open}` and
  # `{:error, :closed} -> {acc, :closed}`, over whatever was in `acc`, INCLUDING NOTHING. An
  # empty buffer was reported as a measurement and every assertion downstream was made against
  # bytes that had never arrived -- so the failure surfaced as `assert bytes =~ "HTTP/1.1 403"`,
  # a sentence about the server, for a fault entirely on this side of the wire.
  @read_ms 10_000

  defp collect(sock, acc, expect) do
    if complete_responses(acc) >= expect do
      settle(sock, acc)
    else
      receive do
        {:tcp, ^sock, data} ->
          collect(sock, acc <> data, expect)

        {:tcp_error, ^sock, reason} ->
          {:aborted, reason, acc}

        {:tcp_closed, ^sock} ->
          {:unanswered, acc}
      after
        @read_ms ->
          raise """
          No further bytes for #{@read_ms} ms with #{complete_responses(acc)} complete \
          response(s) out of #{expect}. #{byte_size(acc)} byte(s) were read.

          This is a stuck read, not a verdict about the connection.
          """
      end
    end
  end

  defp aborted(reason, acc, expect, attempts) do
    """
    #{attempts} exchange(s) in a row were aborted before a measurement existed. The last ended \
    (#{inspect(reason)}) after #{complete_responses(acc)} complete response(s) out of \
    #{expect}, having read #{byte_size(acc)} byte(s): \
    #{inspect(acc, limit: 400, printable_limit: 400)}

    One aborted exchange is a lost segment and is repeated. #{attempts} of them is not, and it \
    is reported here rather than turned into an assertion about bytes nobody received.
    """
  end

  # A CLEAN CLOSE IS NEVER REPEATED, AND THAT DISTINCTION IS THE WHOLE OF ROUND 1's FINDING B2.
  #
  # The repeat used to fire on `{:tcp_closed, ...}` too. Round 1 lane m built a listener that
  # stays silent on four connections and answers on the fifth, and the suite PASSED -- an
  # intermittently broken server laundered into a green run by the very mechanism added to stop
  # a false verdict. Repeating a silence is indistinguishable from believing it away.
  #
  # A FIN and an RST are different statements and the harness now reads them as different. The
  # server closing cleanly having answered nothing is the server saying it has nothing to say:
  # a measurement, and a damning one. Only an ABORT can destroy a response that was written,
  # which is what `slices/006-harness-honesty/logs/probe-loss-reason.txt` measures against the
  # real listener -- every genuine loss arrives as `:econnreset`, never as a clean close.
  defp unanswered(acc, expect) do
    """
    The server closed the connection without answering: #{complete_responses(acc)} complete \
    response(s) out of #{expect}, #{byte_size(acc)} byte(s) read: \
    #{inspect(acc, limit: 400, printable_limit: 400)}

    This is NOT repeated. A clean close is the server's answer, not a lost one -- only an abort \
    can destroy a response already written. Repeating this would turn an intermittently silent \
    server into a passing suite.
    """
  end

  # WHETHER THE SERVER CLOSED IS ONLY ASKED ONCE THE RESPONSES ARE ALREADY COMPLETE, and that
  # ordering is what makes the remaining window safe. TCP delivers a FIN in order, behind the
  # bytes that preceded it, and the driver posts `{:tcp_closed, ...}` after the `{:tcp, ...}`
  # messages it already posted -- so a server that closes after answering has already queued its
  # FIN by the time the last byte of the last response is in hand. This window is not racing the
  # response bytes; it is racing only the server's own close syscall.
  #
  # It is still a window, and it is named as one. `:open` is the ABSENCE of an event and cannot
  # be decided any other way over a socket. What it can no longer do is report a verdict over a
  # buffer that is empty or short, which is the defect this replaces.
  #
  # Anything that arrives during it is kept, so `responses/1` still counts everything the server
  # sent and an assertion on that count is not made vacuous by `expect`.
  @hold_ms 700

  defp settle(sock, acc) do
    receive do
      {:tcp, ^sock, data} -> settle(sock, acc <> data)
      {:tcp_closed, ^sock} -> {acc, :closed}
      {:tcp_error, ^sock, _reason} -> {acc, :closed}
    after
      @hold_ms -> {acc, :open}
    end
  end

  # A response is complete when its `content-length` bytes have arrived. Every response this
  # adapter sends declares one, so this needs no chunked-encoding limb; a response without one
  # simply never counts as complete and the read raises rather than guessing.
  defp complete_responses(bytes), do: complete_responses(bytes, 0)

  defp complete_responses(bytes, n) do
    with ["HTTP/1.1 " <> _ = head, rest] <- String.split(bytes, "\r\n\r\n", parts: 2),
         {:ok, len} <- content_length(head),
         true <- byte_size(rest) >= len do
      complete_responses(binary_part(rest, len, byte_size(rest) - len), n + 1)
    else
      _ -> n
    end
  end

  defp content_length(head) do
    head
    |> String.downcase()
    |> String.split("\r\n")
    |> Enum.find_value(:error, fn
      "content-length:" <> v -> {:ok, String.to_integer(String.trim(v))}
      _ -> nil
    end)
  end

  defp responses(bytes), do: length(String.split(bytes, "HTTP/1.1 ")) - 1

  # A raw listener with a scripted reply, so the harness's own reading can be given inputs the
  # adapter under test cannot be made to produce on demand. CONVENTIONS.md: an anchor that
  # cannot move under the mutation carries no information, and the two tests at the bottom of
  # this file are the anchors for everything above -- without them the read logic is argued in
  # a comment and pinned by nothing.
  defp fake_listener(handler) do
    {:ok, lsock} =
      :gen_tcp.listen(0, [:binary, active: false, packet: :raw, reuseaddr: true, ip: :loopback])

    {:ok, lport} = :inet.port(lsock)

    spawn(fn -> accept_forever(lsock, handler) end)
    on_exit(fn -> :gen_tcp.close(lsock) end)
    lport
  end

  defp accept_forever(lsock, handler) do
    case :gen_tcp.accept(lsock) do
      {:ok, sock} ->
        spawn(fn -> handler.(sock) end)
        accept_forever(lsock, handler)

      {:error, _closed} ->
        :ok
    end
  end

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

      {bytes, state} = exchange(port, good_post(1) <> good_post(2), 2)

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

      {bytes, state} = exchange(port, req("POST", bad_json) <> good_post(2), 2)

      assert String.contains?(bytes, "HTTP/1.1 400")
      assert responses(bytes) == 2
      assert state == :open
      refute closes?(bytes)
    end

    # THE POPULATION IS DERIVED, NOT LISTED, per CONVENTIONS.md's "every place a mechanism
    # reads the same kind of input is one mechanism". The set is the steps of `before_body/2`
    # in `lib/beam_mcp/transport/http.ex`, and it was derived with:
    #
    #     $ grep -n 'defp before_body' -A 10 lib/beam_mcp/transport/http.ex
    #     $ grep -n '{:refused,' lib/beam_mcp/transport/http.ex
    #
    # The first shows the steps on the near side of the body read and the read itself; the
    # second lists every refusal site in the module, to be placed against those steps. Three of
    # the second grep's fourteen hits are not sites -- the comment quoting itself, `handle/2`'s
    # `else`, and `before_body/2`'s own close -- so the hits are read, not counted.
    #
    # SEVEN sites are at or before the read: the Origin 403, the 405, `authorize/1`'s 500, its
    # 403 and its contract-violation 403, and `read_body_bounded/1`'s own 413 and 400. Exactly
    # one, the 413, already closed. The brief this work came from named three.
    #
    # A case per STEP, with the sites named, because a step is what a future change adds -- and
    # a step added to `before_body/2` inherits the behaviour without needing a new finding.

    test "an Origin refusal ends the connection instead of draining the body it refused" do
      port = listen(allowed_origins: ["https://good.example"])

      {bytes, state} =
        exchange(port, unfinished("POST", [{"origin", "https://evil.example"}]), 1)

      assert String.contains?(bytes, "HTTP/1.1 403")
      assert closes?(bytes)
      # THE EFFECT, which is what makes this an anchor rather than a string check: the server
      # ends the connection instead of reading megabytes for a caller it just refused. Without
      # the header Bandit keeps the connection and drains, and this reads `:open`.
      assert state == :closed
    end

    test "an authorize refusal ends the connection instead of draining the body it refused" do
      port = listen(authorize: fn _conn -> {:error, :nope} end)

      {bytes, state} = exchange(port, unfinished("POST"), 1)

      assert String.contains?(bytes, "HTTP/1.1 403")
      assert closes?(bytes)
      assert state == :closed
    end

    test "an authorize that raises ends the connection instead of draining the body" do
      # The 500 limb: a different `{:refused, ...}` site in the same step, and the limb slice
      # 002's lane s3 probed.
      port = listen(authorize: fn _conn -> raise "authorize exploded" end)

      {bytes, state} = exchange(port, unfinished("POST"), 1)

      assert String.contains?(bytes, "HTTP/1.1 500")
      assert closes?(bytes)
      assert state == :closed
    end

    test "an authorize breaking its contract ends the connection instead of draining" do
      # The third `{:refused, ...}` site in the same step: a host returning neither `:ok` nor
      # `{:error, reason}` is failed closed with a 403. Named separately because "the authorize
      # 403" reads like one site and is two.
      port = listen(authorize: fn _conn -> :yes_please end)

      {bytes, state} = exchange(port, unfinished("POST"), 1)

      assert String.contains?(bytes, "HTTP/1.1 403")
      assert closes?(bytes)
      assert state == :closed
    end

    test "a 405 ends the connection instead of draining the body it refused" do
      # A PUT WITH A BODY, not a GET. A GET leaves nothing unread, so it would pass whether or
      # not the header is sent and would pin nothing. The method check refuses every non-POST,
      # and a non-POST is free to carry a body.
      port = listen([])

      {bytes, state} = exchange(port, unfinished("PUT"), 1)

      assert String.contains?(bytes, "HTTP/1.1 405")
      assert String.downcase(bytes) =~ "allow: post"
      assert closes?(bytes)
      assert state == :closed
    end

    test "a refusal over the adapter's drain cap now announces the close it always did" do
      # THE CASE WHERE THE CLIENT WAS TOLD NOTHING. Above bandit's 8_000_000-byte drain cap the
      # drain fails, the adapter logs `Unable to read remaining data in request body` and drops
      # the connection -- pipelined request lost, no `connection: close` in the response that
      # preceded it. Measured before the fix in
      # `slices/003-release-0-3-1/logs/probe-d-bandit-drain-limits.txt`:
      #
      #     authorize 403, 9000160-byte body   responses=1  socket=closed
      #
      # The connection ended either way. What changes is that the client is now told.
      port = listen(authorize: fn _conn -> {:error, :nope} end)

      big = call_json(1, @over_drain_cap)

      {bytes, state} = exchange(port, req("POST", big) <> good_post(2), 1)

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

      {bytes, state} = exchange(port, req("POST", big) <> good_post(2), 1)

      assert String.contains?(bytes, "HTTP/1.1 413")
      assert closes?(bytes)
      assert state == :closed
    end
  end

  describe "the harness itself: what it will and will not report as a measurement" do
    test "a response split across the hold window is read whole, not cut at it" do
      # THE ANCHOR FOR THE COMPLETENESS CHANGE. `drain/2` ended the read on @quiet_ms of
      # silence, so a response whose body lagged its headers by longer than that came back
      # TRUNCATED and the connection came back `:open` -- a verdict, from a partial buffer.
      # Completeness now comes from `content-length`, so the gap is irrelevant.
      body = String.duplicate("z", 4_000)
      head = "HTTP/1.1 200 OK\r\ncontent-length: #{byte_size(body)}\r\n\r\n"

      port =
        fake_listener(fn sock ->
          :gen_tcp.send(sock, head)
          Process.sleep(@hold_ms * 2)
          :gen_tcp.send(sock, body)
          :gen_tcp.close(sock)
        end)

      {bytes, state} = exchange(port, "GET / HTTP/1.1\r\nhost: x\r\n\r\n", 1)

      assert byte_size(bytes) == byte_size(head) + byte_size(body)
      assert state == :closed
    end

    test "an aborted connection is repeated, and the repeat is announced" do
      # THE POSITIVE ANCHOR FOR THE REPEAT, and it exists because round 1 lane m showed the old
      # one was CONTAINED: it interpolated #{@attempts} into its own expected message, so the
      # constant sat on both sides and could not disagree with itself. Setting @attempts to 1 --
      # deleting the repeat outright -- left the whole suite green.
      #
      # This one fails if the repeat is removed, because the first exchange is aborted and only
      # a repeat can reach the answer. SO_LINGER 0 makes close/1 send an RST rather than a FIN,
      # which is the real listener's behaviour when it closes with a body still unread.
      body = String.duplicate("z", 64)
      head = "HTTP/1.1 200 OK\r\ncontent-length: #{byte_size(body)}\r\n\r\n"
      seen = :counters.new(1, [])

      port =
        fake_listener(fn sock ->
          # Read first, so the abort is ordered AFTER the request rather than racing it.
          _ = :gen_tcp.recv(sock, 0, 2_000)

          if :counters.get(seen, 1) == 0 do
            :counters.add(seen, 1, 1)
            :inet.setopts(sock, [{:linger, {true, 0}}])
          else
            :gen_tcp.send(sock, head <> body)
          end

          :gen_tcp.close(sock)
        end)

      announced =
        capture_io(:stderr, fn ->
          send(self(), {:exchanged, exchange(port, "GET / HTTP/1.1\r\nhost: x\r\n\r\n", 1)})
        end)

      assert_received {:exchanged, {bytes, state}}
      assert byte_size(bytes) == byte_size(head) + byte_size(body)
      assert state == :closed
      assert announced =~ "produced no measurement"
    end

    test "a server that closes without answering is reported at once, and is NOT repeated" do
      # ROUND 1 LANE m's ATTACK, kept as a test. A listener silent on the first four connections
      # and answering on the fifth used to PASS: the repeat walked past four refusals to reach an
      # answer, which is laundering an intermittently broken server rather than measuring it.
      # A clean close is now a measurement and stops the exchange dead.
      seen = :counters.new(1, [])

      port =
        fake_listener(fn sock ->
          _ = :gen_tcp.recv(sock, 0, 2_000)
          :counters.add(seen, 1, 1)

          if :counters.get(seen, 1) > 4 do
            body = "{}"
            :gen_tcp.send(sock, "HTTP/1.1 200 OK\r\ncontent-length: 2\r\n\r\n" <> body)
          end

          :gen_tcp.close(sock)
        end)

      announced =
        capture_io(:stderr, fn ->
          assert_raise RuntimeError, ~r/closed the connection without answering/, fn ->
            exchange(port, "GET / HTTP/1.1\r\nhost: x\r\n\r\n", 1)
          end
        end)

      # The absence of a repeat is the whole assertion: one silence, one report.
      refute announced =~ "produced no measurement"
      assert :counters.get(seen, 1) == 1
    end

    test "a connection aborted every time raises after the bound instead of looping" do
      # The bound is written as a LITERAL here. @attempts appears on the other side of this
      # comparison only, so raising or lowering it breaks this test instead of moving with it.
      port =
        fake_listener(fn sock ->
          _ = :gen_tcp.recv(sock, 0, 2_000)
          :inet.setopts(sock, [{:linger, {true, 0}}])
          :gen_tcp.close(sock)
        end)

      capture_io(:stderr, fn ->
        assert_raise RuntimeError,
                     ~r/^5 exchange\(s\) in a row were aborted/,
                     fn -> exchange(port, "GET / HTTP/1.1\r\nhost: x\r\n\r\n", 1) end
      end)
    end
  end
end
