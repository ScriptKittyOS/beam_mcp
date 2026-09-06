# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.ErrorPayloadTest do
  @moduledoc """
  An error crossing the wire carries JSON, not Elixir.

  A client has no reason to know what language the server is written in, and no way to parse
  its term syntax. `inspect/1` output in a response is both unusable and a disclosure of
  implementation detail across the boundary this package exists to keep clean.
  """
  use ExUnit.Case, async: true

  alias BeamMCP.Server

  defmodule Catalog do
    @behaviour BeamMCP.ToolCatalog

    @impl true
    def all do
      [
        %BeamMCP.ToolSpec{
          name: :widget,
          command_class: :observe,
          mode: :read_only,
          description: "d",
          input_schema: %{
            "type" => "object",
            "properties" => %{"a" => %{"type" => "string"}},
            "required" => ["a"]
          }
        }
      ]
    end
  end

  defp call(dispatch, args) do
    Server.new(tool_catalog: Catalog, dispatch: dispatch)
    |> Server.handle_message(%{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "tools/call",
      "params" => %{"name" => "widget", "arguments" => args}
    })
    |> elem(1)
  end

  defp ok_dispatch, do: fn _n, a, _o -> {:ok, a} end

  # Elixir syntax that must never appear in a wire payload: map literals, bare atoms.
  defp elixir_syntax?(text), do: text =~ ~r/%\{|(?<![\w:]):[a-z_]+\b/

  test "a validation failure carries structured fields, not an inspected map" do
    r = call(ok_dispatch(), %{})

    err = r["result"]["structuredContent"]["error"]

    assert is_map(err), "the error is a JSON object a client can read, not a stringified term"
    assert err["tool"] == "widget"
    assert err["reason"] =~ "required"
    refute elixir_syntax?(Jason.encode!(err))
  end

  test "the human-readable content carries no Elixir syntax either" do
    r = call(ok_dispatch(), %{})

    text = hd(r["result"]["content"])["text"]

    refute elixir_syntax?(text),
           "the text a user is shown must not be an inspected Elixir term: #{text}"

    assert text =~ "widget"
    assert text =~ "required"
  end

  test "a host's error term is carried as JSON, not as an inspected term" do
    r =
      call(fn _n, _a, _o -> {:error, %{code: "upstream_timeout", retry_after: 30}} end, %{
        "a" => "x"
      })

    err = r["result"]["structuredContent"]["error"]

    assert err["code"] == "upstream_timeout"
    assert err["retry_after"] == 30
    refute elixir_syntax?(Jason.encode!(err))
  end

  test "a host's plain-string error survives unchanged" do
    r = call(fn _n, _a, _o -> {:error, "upstream unavailable"} end, %{"a" => "x"})

    assert r["result"]["structuredContent"]["error"] == "upstream unavailable"
    assert hd(r["result"]["content"])["text"] == "upstream unavailable"
  end

  test "every error result is still flagged isError" do
    assert call(ok_dispatch(), %{})["result"]["isError"]
    assert call(fn _n, _a, _o -> {:error, "x"} end, %{"a" => "y"})["result"]["isError"]
  end
end
