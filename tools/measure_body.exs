# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# Settles the README's read-before-refusal sentence by measuring the two quantities it used to
# state as one. Run with `mix run tools/measure_body.exs`; the archive it produced is
# slices/002-streamable-http/logs/measure-read-before-refusal.txt.
#
# The sentence has been wrong twice -- first a single exact byte count no lane could reproduce,
# then a 1.02-1.50 MiB range attributed to the client's send buffer. It is a script rather than
# a note so the next person re-measures instead of re-deriving.
# Two DIFFERENT quantities the README currently states as one.
#   A: how many bytes the SERVER reads before it refuses  -- Plug.Conn.read_body/2's partial
#   B: how many bytes the CLIENT gets onto the wire before the refusal arrives
defmodule Probe do
  @behaviour Plug
  @max 1_048_576
  def init(o), do: o
  def call(conn, _o) do
    case Plug.Conn.read_body(conn, length: @max) do
      {:more, partial, conn} ->
        send(:collector, {:server_read, byte_size(partial)})
        conn |> Plug.Conn.put_resp_content_type("application/json") |> Plug.Conn.send_resp(413, "{}")
      {:ok, body, conn} ->
        send(:collector, {:server_read, byte_size(body)})
        Plug.Conn.send_resp(conn, 200, "{}")
      {:error, r} ->
        send(:collector, {:server_error, r})
        Plug.Conn.send_resp(conn, 400, "{}")
    end
  end
end

Process.register(self(), :collector)
{:ok, _} = Bandit.start_link(plug: Probe, port: 4931, ip: {127,0,0,1})
Process.sleep(300)

declared = 32 * 1024 * 1024
chunk = :binary.copy("x", 65536)

measure = fn sndbuf ->
  opts = [:binary, active: false, packet: :raw] ++ (if sndbuf, do: [sndbuf: sndbuf], else: [])
  {:ok, sock} = :gen_tcp.connect(~c"127.0.0.1", 4931, opts)
  head = "POST /mcp HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: #{declared}\r\n\r\n"
  :ok = :gen_tcp.send(sock, head)

  # Write until the server answers (or we finish the declared length).
  written =
    Enum.reduce_while(1..(div(declared, byte_size(chunk))), 0, fn _, acc ->
      case :gen_tcp.recv(sock, 0, 0) do
        {:ok, _resp} -> {:halt, acc}
        _ ->
          case :gen_tcp.send(sock, chunk) do
            :ok -> {:cont, acc + byte_size(chunk)}
            {:error, _} -> {:halt, acc}
          end
      end
    end)

  server_read = receive do
    {:server_read, n} -> n
    {:server_error, r} -> {:error, r}
  after 5000 -> :no_report end

  :gen_tcp.close(sock)
  {sndbuf, written, server_read}
end

IO.puts("declared Content-Length: #{declared} bytes (32 MiB)")
IO.puts("@max_body_bytes:         1048576 bytes (1 MiB)\n")
IO.puts(String.pad_trailing("sndbuf", 12) <> String.pad_trailing("B: client wrote", 20) <> "A: server read before refusing")
for sndbuf <- [nil, 4096, 16384, 65536, 262144, 1048576] do
  {s, written, server_read} = measure.(sndbuf)
  label = if s, do: Integer.to_string(s), else: "default"
  IO.puts(String.pad_trailing(label, 12) <>
          String.pad_trailing("#{written} (#{Float.round(written / 1048576, 3)} MiB)", 20) <>
          "#{inspect(server_read)}")
  Process.sleep(100)
end
