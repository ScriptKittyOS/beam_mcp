# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Run with: MIX_ENV=test mix run tools/probes/<this file>   (N=<runs> in the environment)
# WHERE ARE THE 297 BYTES LOST? Three places are possible and they need different fixes:
#   1. the server never wrote them              -> a server-side effect, not a harness bug
#   2. the client's socket never received them  -> the RST beat the data on the wire
#   3. the client's socket received them and the RST/teardown discarded them
#
# `:inet.getstat(sock, [:recv_oct])` counts bytes the CLIENT SOCKET took off the wire, which
# separates 2 from 3. The plug's `authorize` callback messages this process, which separates 1.
alias BeamMCP.Transport.HTTP

defmodule Cat do
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

n = String.to_integer(System.get_env("N", "60"))
over = 9_000_000
modern = "2026-07-28"
vkey = "io.modelcontextprotocol/protocolVersion"
owner = self()

opts = [
  tool_catalog: Cat,
  dispatch: fn _n, a, _o -> {:ok, a} end,
  authorize: fn _conn ->
    send(owner, :authorize_ran)
    {:error, :nope}
  end,
  allowed_origins: :any
]

{:ok, pid} = Bandit.start_link(plug: {HTTP, opts}, port: 0, ip: :loopback, startup_log: false)
{:ok, {_a, port}} = ThousandIsland.listener_info(pid)

body =
  Jason.encode!(%{
    "jsonrpc" => "2.0",
    "id" => 1,
    "method" => "tools/call",
    "params" => %{"name" => "echo", "arguments" => %{}},
    "_meta" => %{vkey => modern},
    "pad" => String.duplicate("x", over)
  })

payload =
  "POST /mcp HTTP/1.1\r\nhost: localhost\r\ncontent-type: application/json\r\n" <>
    "content-length: #{byte_size(body)}\r\nmcp-protocol-version: #{modern}\r\n" <>
    "mcp-method: tools/call\r\nmcp-name: echo\r\n\r\n" <> body

flush = fn flush ->
  receive do
    :authorize_ran -> flush.(flush)
  after
    0 -> :ok
  end
end

collect = fn collect, sock, acc ->
  receive do
    {:tcp, ^sock, d} -> collect.(collect, sock, acc <> d)
    {:tcp_error, ^sock, r} -> {acc, r}
    {:tcp_closed, ^sock} -> {acc, :closed}
  after
    10_000 -> {acc, :timeout}
  end
end

write_all = fn
  _write, _sock, "" -> :ok
  write, sock, rest ->
    take = min(byte_size(rest), 65_536)
    chunk = binary_part(rest, 0, take)

    case :gen_tcp.send(sock, chunk) do
      :ok -> write.(write, sock, binary_part(rest, take, byte_size(rest) - take))
      err -> err
    end
end

one = fn shape ->
  flush.(flush)
  me = self()

  {:ok, sock} =
    :gen_tcp.connect(
      ~c"127.0.0.1",
      port,
      [:binary, active: true, packet: :raw, show_econnreset: true],
      5_000
    )

  spawn(fn ->
    r =
      case shape do
        :one_send -> :gen_tcp.send(sock, payload)
        :chunked -> write_all.(write_all, sock, payload)
      end

    send(me, {:written, r})
  end)
  {acc, reason} = collect.(collect, sock, "")

  stat =
    case :inet.getstat(sock, [:recv_oct, :recv_cnt]) do
      {:ok, s} -> s
      other -> other
    end

  authorized =
    receive do
      :authorize_ran -> true
    after
      2_000 -> false
    end

  :gen_tcp.close(sock)
  {byte_size(acc), reason, stat, authorized}
end

for shape <- [:one_send, :chunked] do
  results = for _ <- 1..n, do: one.(shape)

  IO.puts("\n== #{shape}: #{n} runs of the 9 MB refusal, active-mode client ==")
  IO.puts("   {bytes delivered to the process, end reason, socket stats, authorize/1 ran?}")

  results
  |> Enum.frequencies()
  |> Enum.sort_by(fn {_k, v} -> -v end)
  |> Enum.each(fn {k, v} -> IO.puts("   #{v}x  #{inspect(k)}") end)

  IO.puts("   response MISSING in #{Enum.count(results, fn {b, _, _, _} -> b == 0 end)}/#{n}")
end

IO.puts("\nPROBE_DONE")
