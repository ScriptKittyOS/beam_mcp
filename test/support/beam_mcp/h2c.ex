# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.H2C do
  @moduledoc """
  The smallest HTTP/2 client that can drip a request body: cleartext with prior knowledge
  (the preface `Bandit` sniffs on a plaintext listener), one stream, HPACK literals without
  indexing and without Huffman coding, so nothing here needs a table. Written because the
  suite had no HTTP/2 client and a review lane showed the transport's whole-body deadline
  defeated over HTTP/2 -- a per-frame clock inside the adapter -- while every test spoke
  HTTP/1.1.

  `open/2` connects and sends the preface, an empty SETTINGS and the request HEADERS (with
  END_HEADERS, without END_STREAM); `data/3` sends one DATA frame; `finish/1` an empty DATA
  with END_STREAM; `response/2` reads frames until the stream's HEADERS and DATA have arrived
  (or RST_STREAM, or the timeout), returning `{:ok, headers_block, body}` -- the block raw,
  since decoding Huffman is not this client's business -- or `{:rst, code}` or `:timeout`.
  """

  import Bitwise

  @preface "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"
  @stream 1

  def open(port, headers) do
    {:ok, sock} =
      :gen_tcp.connect(~c"127.0.0.1", port, [:binary, active: false, packet: :raw], 2_000)

    :ok = :gen_tcp.send(sock, @preface)
    :ok = :gen_tcp.send(sock, frame(0x4, 0x0, 0, <<>>))
    :ok = :gen_tcp.send(sock, frame(0x1, 0x4, @stream, hpack(headers)))
    sock
  end

  def data(sock, bytes, end_stream? \\ false),
    do: :gen_tcp.send(sock, frame(0x0, if(end_stream?, do: 0x1, else: 0x0), @stream, bytes))

  def finish(sock), do: data(sock, <<>>, true)

  def close(sock), do: :gen_tcp.close(sock)

  def response(sock, timeout_ms) do
    state = %{sock: sock, deadline: System.monotonic_time(:millisecond) + timeout_ms}
    read_frames(state, <<>>, nil, <<>>)
  end

  defp read_frames(state, buffer, headers, body) do
    case parse(buffer) do
      {:frame, type, flags, stream, payload, rest} ->
        handle({type, flags, stream}, payload, state, rest, headers, body)

      :more ->
        recv_more(state, buffer, headers, body)
    end
  end

  defp recv_more(%{sock: sock, deadline: deadline} = state, buffer, headers, body) do
    remaining = deadline - System.monotonic_time(:millisecond)

    case remaining > 0 and :gen_tcp.recv(sock, 0, remaining) do
      {:ok, bytes} -> read_frames(state, buffer <> bytes, headers, body)
      {:error, :closed} when headers != nil -> {:ok, headers, body}
      {:error, :closed} -> {:closed, body}
      _ -> :timeout
    end
  end

  # SETTINGS from the server are acknowledged; PING answered; everything on stream 0 else
  # ignored. On our stream: HEADERS is the response head, DATA its body, END_STREAM the end.
  defp handle({0x4, 0x0, 0}, _payload, state, rest, headers, body) do
    :ok = :gen_tcp.send(state.sock, frame(0x4, 0x1, 0, <<>>))
    read_frames(state, rest, headers, body)
  end

  defp handle({0x6, 0x0, 0}, payload, state, rest, headers, body) do
    :ok = :gen_tcp.send(state.sock, frame(0x6, 0x1, 0, payload))
    read_frames(state, rest, headers, body)
  end

  defp handle({0x3, _flags, @stream}, <<code::32>>, _state, _rest, _headers, _body),
    do: {:rst, code}

  defp handle({0x7, _flags, 0}, <<_::32, code::32, _::binary>>, _state, _rest, _headers, _body),
    do: {:goaway, code}

  defp handle({0x1, flags, @stream}, payload, state, rest, _headers, body) do
    block = strip_padding_and_priority(payload, flags)
    if end_stream?(flags), do: {:ok, block, body}, else: read_frames(state, rest, block, body)
  end

  defp handle({0x0, flags, @stream}, payload, state, rest, headers, body) do
    body = body <> strip_padding(payload, flags)
    if end_stream?(flags), do: {:ok, headers, body}, else: read_frames(state, rest, headers, body)
  end

  defp handle(_frame, _payload, state, rest, headers, body),
    do: read_frames(state, rest, headers, body)

  defp end_stream?(flags), do: (flags &&& 0x1) == 0x1

  defp strip_padding(payload, flags) when (flags &&& 0x8) == 0x8 do
    <<pad::8, rest::binary>> = payload
    binary_part(rest, 0, byte_size(rest) - pad)
  end

  defp strip_padding(payload, _flags), do: payload

  defp strip_padding_and_priority(payload, flags) do
    payload = strip_padding(payload, flags)

    if (flags &&& 0x20) == 0x20,
      do: binary_part(payload, 5, byte_size(payload) - 5),
      else: payload
  end

  defp parse(<<len::24, type::8, flags::8, _r::1, stream::31, rest::binary>>)
       when byte_size(rest) >= len do
    <<payload::binary-size(len), tail::binary>> = rest
    {:frame, type, flags, stream, payload, tail}
  end

  defp parse(_), do: :more

  defp frame(type, flags, stream, payload),
    do: <<byte_size(payload)::24, type::8, flags::8, 0::1, stream::31, payload::binary>>

  # Literal header field without indexing, new name (0x00), string lengths as plain 7-bit
  # integers (every name and value here is under 127 bytes), no Huffman.
  defp hpack(headers) do
    for {name, value} <- headers, into: <<>> do
      <<0x00, byte_size(name)::8, name::binary, byte_size(value)::8, value::binary>>
    end
  end
end
