# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run with: MIX_ENV=test mix run tools/probes/<this file>   (N=<runs> in the environment)
# Why does `bytes` come back EMPTY from the 9 MB refusal case?
#
# The PLAN's hypothesis is the 700 ms quiet window returning a PARTIAL buffer. The measured
# failure argument is "" -- an EMPTY buffer -- and the whole suite finished in 3.5 s, so the
# 10_000 ms first-byte window was never reached either. This probe asks which socket result
# `drain/2` actually saw, and whether the bytes were LOST rather than late.
#
# Four variants of the same exchange, each run N times:
#   A  send-everything-then-read, show_econnreset default(false)   <- what the test does today
#   B  send-everything-then-read, show_econnreset: true
#   C  read concurrently with the write, show_econnreset default
#   D  read concurrently with the write, show_econnreset: true
alias BeamMCP.Transport.HTTP

defmodule Cat do
  @behaviour BeamMCP.Catalog
  @impl true
  def capabilities do
    tools = [
      %BeamMCP.ToolSpec{
        name: :echo,
        command_class: :observe,
        mode: :read_only,
        description: "Echo.",
        input_schema: %{"type" => "object", "properties" => %{}, "additionalProperties" => true}
      }
    ]

    %{tools: tools, resources: [], prompts: []}
  end
end

n = String.to_integer(System.get_env("N", "20"))
over = 9_000_000
modern = "2026-07-28"
vkey = "io.modelcontextprotocol/protocolVersion"

opts = [
  catalog: Cat,
  dispatch: fn _n, a, _o -> {:ok, a} end,
  authorize: fn _conn -> {:error, :nope} end,
  allowed_origins: :any
]

{:ok, pid} =
  Bandit.start_link(plug: {HTTP, opts}, port: 0, ip: :loopback, startup_log: false)

{:ok, {_a, port}} = ThousandIsland.listener_info(pid)

call_json = fn id, pad ->
  Jason.encode!(%{
    "jsonrpc" => "2.0",
    "id" => id,
    "method" => "tools/call",
    "params" => %{"name" => "echo", "arguments" => %{}},
    "_meta" => %{vkey => modern},
    "pad" => String.duplicate("x", pad)
  })
end

req = fn method, body ->
  "#{method} /mcp HTTP/1.1\r\nhost: localhost\r\ncontent-type: application/json\r\n" <>
    "content-length: #{byte_size(body)}\r\nmcp-protocol-version: #{modern}\r\n" <>
    "mcp-method: tools/call\r\nmcp-name: echo\r\n\r\n" <> body
end

big = req.("POST", call_json.(1, over))
second = req.("POST", call_json.(2, 0))
payload = big <> second

# The test's drain/2, verbatim, but reporting the RAW socket result instead of a verdict.
drain = fn drain, sock, acc, first_ms, quiet_ms ->
  t = if acc == "", do: first_ms, else: quiet_ms

  case :gen_tcp.recv(sock, 0, t) do
    {:ok, data} -> drain.(drain, sock, acc <> data, first_ms, quiet_ms)
    {:error, reason} -> {acc, reason}
  end
end

run = fn concurrent?, econnreset? ->
  base = [:binary, active: false, packet: :raw]
  sockopts = if econnreset?, do: base ++ [show_econnreset: true], else: base
  {:ok, sock} = :gen_tcp.connect(~c"127.0.0.1", port, sockopts, 5_000)

  send_res =
    if concurrent? do
      me = self()
      spawn(fn -> send(me, {:sent, :gen_tcp.send(sock, payload)}) end)
      :spawned
    else
      :gen_tcp.send(sock, payload)
    end

  {acc, reason} = drain.(drain, sock, "", 10_000, 700)

  send_res =
    if concurrent? do
      receive do
        {:sent, r} -> r
      after
        5_000 -> :writer_still_running
      end
    else
      send_res
    end

  :gen_tcp.close(sock)
  {byte_size(acc), reason, send_res, String.contains?(acc, "HTTP/1.1 403")}
end

for {label, conc, ecr} <- [
      {"A  send-all-then-read, show_econnreset default", false, false},
      {"B  send-all-then-read, show_econnreset: true", false, true},
      {"C  concurrent read+write, show_econnreset default", true, false},
      {"D  concurrent read+write, show_econnreset: true", true, true}
    ] do
  results = for _ <- 1..n, do: run.(conc, ecr)

  tally =
    results
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_k, v} -> -v end)

  IO.puts("\n== #{label}  (#{n} runs) ==")
  IO.puts("   {bytes_received, recv_reason, send_result, saw_403?}")

  for {k, v} <- tally, do: IO.puts("   #{v}x  #{inspect(k)}")

  bad = Enum.count(results, fn {_, _, _, saw} -> not saw end)
  IO.puts("   403 MISSING in #{bad}/#{n}")
end

IO.puts("\nPROBE_DONE")
