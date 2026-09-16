# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Transport.Stdio do
  @moduledoc """
  The stdio transport: newline-delimited JSON-RPC on standard input and output.

  This is the transport an MCP client launches as a child process, and `run/1` is the whole of
  its public surface. It reads one JSON message per line, hands it to `BeamMCP.Server`, and
  writes the response as one line. A message that cannot be decoded is answered `-32700` and the
  loop continues; end of input ends it.

  Responses are always newline-delimited. A request may arrive under the older `Content-Length`
  framing and is read, because a client that speaks it is not wrong to try — but nothing is
  written back in that form.

  Whoever can write to this transport already has the host's privileges, which is why the
  package does not authenticate here and `BeamMCP.Transport.HTTP` requires an `:authorize`
  option with no default.

      BeamMCP.Transport.Stdio.run(
        catalog: MyApp.Catalog,
        dispatch: &MyApp.Dispatch.call/3,
        server_name: "my-app"
      )

  Options are `BeamMCP.Server.new/1`'s; `:catalog` is required.
  """

  alias BeamMCP.Server

  require Logger

  # One line, and one legacy Content-Length frame, are each bounded at 1 MiB, as the HTTP body is.
  @max_line_bytes 1_048_576
  @max_body_bytes 1_048_576

  @doc """
  Runs the read/answer loop on standard input and output until end of input.

  Blocks the calling process. Options are passed to `BeamMCP.Server.new/1`.
  """
  @spec run(keyword()) :: :ok
  def run(opts \\ []) do
    loop(Server.new(opts))
  end

  defp loop(state) do
    case read_message() do
      :eof ->
        :ok

      {:ok, %{} = message} ->
        {next_state, response} = answer(state, message)

        if response do
          write_message(response)
        end

        if Server.shutdown?(next_state) do
          :ok
        else
          loop(next_state)
        end

      {:ok, other} ->
        write_message(
          error(nil, -32_600, "Expected a JSON object, got #{BeamMCP.JSON.type_of(other)}")
        )

        loop(state)

      {:error, reason} ->
        write_message(refusal(reason))
        loop(state)
    end
  end

  # A host fault -- the catalog, the dispatch function or a hook raising, throwing or exiting
  # -- is answered -32603 with the request's id and the loop goes on, as the HTTP transport
  # answers it 500: a fault in one request is not the end of the pipe. The log line carries
  # arities, never arguments (the same frames the :telemetry exception event carries).
  defp answer(state, message) do
    Server.handle_message(state, message)
  catch
    kind, reason ->
      Logger.error(Exception.format(kind, reason, BeamMCP.Stacktrace.arities(__STACKTRACE__)))
      {state, error(Map.get(message, "id"), -32_603, "Internal error")}
  end

  # Every refusal names its cause in the message and carries no data: an inspected term
  # would carry the client's own bytes back to it (a parse error's token) or an internal
  # atom, and neither is the client's business.
  defp refusal({:nesting, _depth, max}),
    do: error(nil, -32_600, "Request body nests deeper than #{max} levels")

  defp refusal({:duplicate_key, key}),
    do: error(nil, -32_600, "Request body repeats a key: duplicate key #{inspect(key)}")

  defp refusal(:frame_too_large),
    do: error(nil, -32_700, "Parse error: line exceeds #{@max_line_bytes} bytes")

  defp refusal(:declared_frame_too_large),
    do: error(nil, -32_700, "Parse error: frame exceeds #{@max_body_bytes} bytes")

  defp refusal(reason) when reason in [:invalid_content_length, :missing_content_length],
    do: error(nil, -32_700, "Parse error: #{reason}")

  defp refusal(_decode_error), do: error(nil, -32_700, "Parse error: body is not valid JSON")

  defp error(id, code, message),
    do: %{"jsonrpc" => "2.0", "id" => id, "error" => %{"code" => code, "message" => message}}

  # MCP stdio framing is newline-delimited JSON-RPC. The spec at 2024-11-05 and every
  # revision since, including both revisions this server speaks:
  #
  #   "Messages are delimited by newlines, and MUST NOT contain embedded newlines."
  #
  # This previously implemented LSP framing (Content-Length headers), so no conformant
  # MCP client could complete a handshake. Content-Length is still accepted on read so
  # existing callers keep working, but responses are always newline-delimited.
  defp read_message do
    case read_line_bounded() do
      :eof ->
        :eof

      {:error, reason} ->
        {:error, reason}

      {:ok_line, line} ->
        trimmed = String.trim_trailing(line, "\r")

        cond do
          trimmed == "" -> read_message()
          content_length_header?(trimmed) -> read_legacy_framed(trimmed)
          true -> decode(trimmed)
        end
    end
  end

  # Reads one newline-terminated line, refusing to allocate past @max_line_bytes.
  # The cap has to bound the read, not merely inspect its result.
  defp read_line_bounded(acc \\ [], size \\ 0)

  # A line of exactly the bound is admitted; the byte past it is the refusal, so "exceeds"
  # is true of every line refused (until 0.6.0 the boundary byte itself was refused).
  defp read_line_bounded(_acc, size) when size > @max_line_bytes do
    drain_line()
    {:error, :frame_too_large}
  end

  defp read_line_bounded(acc, size) do
    case IO.binread(:stdio, 1) do
      :eof when acc == [] -> :eof
      :eof -> {:ok_line, acc |> Enum.reverse() |> IO.iodata_to_binary()}
      {:error, reason} -> {:error, reason}
      "\n" -> {:ok_line, acc |> Enum.reverse() |> IO.iodata_to_binary()}
      byte -> read_line_bounded([byte | acc], size + 1)
    end
  end

  # `BeamMCP.JSON.decode/1` bounds the nesting before the decoder runs (the line is already
  # under the frame bound, so the refusal costs the scan and nothing else).
  # The rest of an over-long line, read byte by byte to its newline (or EOF) and dropped:
  # nothing of it is buffered, and nothing of it is read as the next frame.
  defp drain_line do
    case IO.binread(:stdio, 1) do
      :eof -> :ok
      {:error, _} -> :ok
      "\n" -> :ok
      _ -> drain_line()
    end
  end

  defp decode(body), do: BeamMCP.JSON.decode(body)

  defp content_length_header?(line) do
    line |> String.downcase() |> String.starts_with?("content-length:")
  end

  # Legacy LSP-style framing, retained for callers written against the old behaviour.
  # A declared length over the cap is refused by name -- and its body is read and dropped in
  # chunks, never buffered, so that nothing of it is read as the next frame: a lane put a
  # `tools/call` inside such a body and saw it dispatched.
  defp read_legacy_framed(first_line) do
    with {:ok, length} <- parse_content_length(first_line),
         :ok <- skip_remaining_headers(),
         {:ok, body} <- read_body(length) do
      decode(body)
    else
      {:error, {:declared_frame_too_large, length}} ->
        skip_remaining_headers()
        drain_bytes(length)
        {:error, :declared_frame_too_large}

      {:error, :unexpected_eof} ->
        :eof

      {:error, _} = error ->
        error
    end
  end

  @drain_chunk 65_536

  defp drain_bytes(0), do: :ok

  defp drain_bytes(remaining) do
    case IO.binread(:stdio, min(remaining, @drain_chunk)) do
      :eof -> :ok
      {:error, _} -> :ok
      chunk -> drain_bytes(remaining - byte_size(chunk))
    end
  end

  defp skip_remaining_headers do
    case IO.binread(:stdio, :line) do
      :eof -> :ok
      {:error, reason} -> {:error, reason}
      line -> if String.trim(line) == "", do: :ok, else: skip_remaining_headers()
    end
  end

  defp parse_content_length(line) do
    case String.split(line, ":", parts: 2) do
      [_name, value] ->
        case Integer.parse(String.trim(value)) do
          {length, ""} when length >= 0 and length <= @max_body_bytes ->
            {:ok, length}

          {length, ""} when length > @max_body_bytes ->
            {:error, {:declared_frame_too_large, length}}

          _ ->
            {:error, :invalid_content_length}
        end

      _ ->
        {:error, :missing_content_length}
    end
  end

  defp read_body(length) when is_integer(length) and length >= 0 do
    case IO.binread(:stdio, length) do
      :eof -> {:error, :unexpected_eof}
      {:error, reason} -> {:error, reason}
      body -> {:ok, body}
    end
  end

  # Always newline-delimited, per the MCP stdio binding. Jason never emits a raw
  # newline inside a JSON scalar, so the "MUST NOT contain embedded newlines"
  # requirement holds.
  defp write_message(message) do
    IO.binwrite(:stdio, [Jason.encode!(message), "\n"])
  end
end
