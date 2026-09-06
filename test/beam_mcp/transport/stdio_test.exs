# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Transport.StdioTest do
  @moduledoc """
  The stdio binding, driven with real bytes.

  MCP stdio framing is newline-delimited JSON-RPC. The spec at `2024-11-05`, and every
  revision since: *"Messages are delimited by newlines, and MUST NOT contain embedded
  newlines."* This module once implemented LSP framing instead, so no conformant client could
  complete a handshake; `Content-Length` is still accepted on read, and never emitted.

  These tests could not travel from the tree this package came from: the ones there drove a
  launcher binary and an umbrella root. They drive `run/1` directly instead, through
  `capture_io`, so the framing is exercised without a subprocess.
  """
  use ExUnit.Case, async: false

  alias BeamMCP.Transport.Stdio

  defmodule Catalog do
    @behaviour BeamMCP.ToolCatalog

    @impl true
    def all do
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

  defp opts, do: [tool_catalog: Catalog, dispatch: fn _n, a, _o -> {:ok, a} end]

  # Drive the real loop over a StringIO standing in for stdio. The group leader is what
  # `IO.binread(:stdio, _)` and `IO.binwrite(:stdio, _)` resolve to, so this exercises the
  # actual framing code rather than a reimplementation of it.
  defp drive(input) do
    {:ok, device} = StringIO.open(input, encoding: :latin1)
    original = Process.group_leader()
    Process.group_leader(self(), device)

    try do
      Stdio.run(opts())
    after
      Process.group_leader(self(), original)
    end

    {:ok, {_input, output}} = StringIO.close(device)
    output
  end

  defp request(id, method),
    do: Jason.encode!(%{"jsonrpc" => "2.0", "id" => id, "method" => method}) <> "\n"

  test "a newline-delimited request gets exactly one newline-delimited response" do
    out = drive(request(1, "initialize"))

    lines = out |> String.split("\n", trim: true)
    assert length(lines) == 1
    assert {:ok, decoded} = Jason.decode(hd(lines))
    assert decoded["id"] == 1
    assert decoded["result"]["protocolVersion"] == "2024-11-05"
  end

  test "responses are newline-delimited and never Content-Length framed" do
    out = drive(request(1, "ping"))

    refute out =~ "Content-Length"
    assert String.ends_with?(out, "\n")
    # exactly one trailing newline, so the frame boundary is unambiguous
    refute String.ends_with?(out, "\n\n")
  end

  test "two requests on separate lines produce two responses, in order" do
    out = drive(request(1, "ping") <> request(2, "ping"))

    ids = out |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!(&1)["id"])
    assert ids == [1, 2]
  end

  test "legacy Content-Length input is still accepted on read" do
    body = Jason.encode!(%{"jsonrpc" => "2.0", "id" => 7, "method" => "ping"})
    out = drive("Content-Length: #{byte_size(body)}\r\n\r\n" <> body)

    assert [line] = String.split(out, "\n", trim: true)
    assert Jason.decode!(line)["id"] == 7
  end

  test "malformed JSON gets a parse error, and the loop keeps going" do
    out = drive("{not json\n" <> request(2, "ping"))

    [err, ok] = out |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)
    assert err["error"]["code"] == -32_700
    assert err["error"]["message"] == "Parse error"
    assert ok["id"] == 2
  end

  test "a line beyond the frame bound is refused rather than buffered" do
    out = drive(String.duplicate("x", 1_048_577) <> "\n")

    [first | rest] = out |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)

    assert first["error"]["code"] == -32_700
    assert first["error"]["data"] =~ "frame_too_large"

    # Observed, and asserted so it is not mistaken for a clean refusal: after refusing the
    # oversized frame the loop resumes mid-line, so the remainder is read as a fresh message
    # and produces a second parse error. The bound holds -- nothing beyond it is buffered --
    # but the reader does not resynchronise to the next newline.
    assert length(rest) == 1
    assert hd(rest)["error"]["code"] == -32_700
  end

  test "EOF ends the loop without a response" do
    assert drive("") == ""
  end

  test "shutdown stops the loop, and input after it is not read" do
    out = drive(request(1, "shutdown") <> request(2, "ping"))

    assert [line] = String.split(out, "\n", trim: true)
    assert Jason.decode!(line)["id"] == 1
  end
end
