# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.WireBytesTest do
  @moduledoc """
  The bytes this package writes are the same on every OTP release it runs on.

  A map of more than 32 keys iterates in hash order, and that order is not promised across OTP
  releases: before the sorted encoding, one `tools/list` whose schema had 40 properties hashed
  differently on OTP 28.5.0.8 and OTP 29.1 (the slice record quotes both). A client that
  hashes, caches or signs a response would see a different answer from the same server. So
  every map is written with its keys in sorted order, and this file pins one sha256 per
  response, the same on every leg of CI.

  The responses carry the package's version (`serverInfo` in the result's `_meta`), so a
  release bump changes both hashes, on every leg alike. The rule then: re-pin both from one
  leg in the release's own commit, and confirm the other legs agree in its CI run. A hash that
  moves on one leg and not another is this file's failure, never a re-pin.
  """
  use ExUnit.Case, async: true
  import Plug.Conn
  import Plug.Test

  alias BeamMCP.Transport.HTTP

  @modern "2026-07-28"
  @vkey "io.modelcontextprotocol/protocolVersion"

  # Forty properties, so the schema map and its `properties` map are both past 32 keys.
  @properties Map.new(1..40, fn i ->
                {"p#{String.pad_leading(Integer.to_string(i), 2, "0")}",
                 %{"type" => "string", "description" => "property #{i}"}}
              end)

  defmodule Catalog do
    @moduledoc false
    @behaviour BeamMCP.Catalog

    @impl true
    def capabilities do
      %{
        tools: [
          %BeamMCP.ToolSpec{
            name: :wide,
            command_class: :observe,
            mode: :read_only,
            description: "A tool with a wide schema.",
            input_schema: %{
              "type" => "object",
              "properties" =>
                Map.new(1..40, fn i ->
                  {"p#{String.pad_leading(Integer.to_string(i), 2, "0")}",
                   %{"type" => "string", "description" => "property #{i}"}}
                end),
              "additionalProperties" => false
            }
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
      # A result of 40 keys: the tool's structured result is written as text, too.
      dispatch: fn _name, _args, _opts -> {:ok, Map.new(1..40, &{"k#{&1}", &1})} end,
      authorize: fn _conn -> :ok end,
      allowed_origins: :any
    )
  end

  defp post(method, params, headers) do
    body = %{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => method,
      "params" =>
        Map.put(params, "_meta", %{
          @vkey => @modern,
          "io.modelcontextprotocol/clientCapabilities" => %{}
        })
    }

    conn =
      :post
      |> conn("/mcp", Jason.encode!(body))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("mcp-protocol-version", @modern)
      |> put_req_header("mcp-method", method)

    conn = Enum.reduce(headers, conn, fn {k, v}, c -> put_req_header(c, k, v) end)
    HTTP.call(conn, opts())
  end

  defp sha256(conn) do
    assert conn.status == 200
    :crypto.hash(:sha256, conn.resp_body) |> Base.encode16(case: :lower)
  end

  test "tools/list with a 40-property schema is the same bytes on every OTP release" do
    assert sha256(post("tools/list", %{}, [])) ==
             "40d948fc723e22ad7b81a12c484403e22c80effd39dd212b148ff7a64a4abbf1"
  end

  test "a tools/call whose result has 40 keys is the same bytes on every OTP release" do
    args = Map.new(@properties, fn {k, _} -> {k, "x"} end)
    conn = post("tools/call", %{"name" => "wide", "arguments" => args}, [{"mcp-name", "wide"}])

    assert sha256(conn) ==
             "0bc14b84b3506daf845f3ebcd28e93d3370633f3e2c6113c58dced61de1b9c7f"
  end

  # A refusal is bytes on the wire too: which property it names, and in which order it lists
  # unknown ones, must not depend on the order the client's map iterates in.
  test "a refusal over a 40-key argument map names the first property in sorted order" do
    bad = Map.new(@properties, fn {k, _} -> {k, 1} end)
    conn = post("tools/call", %{"name" => "wide", "arguments" => bad}, [{"mcp-name", "wide"}])
    [%{"text" => text}] = Jason.decode!(conn.resp_body)["result"]["content"]
    assert text =~ "p01", text
    refute Enum.any?(2..40, &(text =~ "p#{String.pad_leading(Integer.to_string(&1), 2, "0")}"))

    extra = Map.new(1..40, &{"q#{String.pad_leading(Integer.to_string(&1), 2, "0")}", "x"})
    conn = post("tools/call", %{"name" => "wide", "arguments" => extra}, [{"mcp-name", "wide"}])
    [%{"text" => text}] = Jason.decode!(conn.resp_body)["result"]["content"]
    listed = Regex.scan(~r/q\d\d/, text) |> List.flatten()
    assert listed == Enum.sort(Map.keys(extra)), text
  end

  test "every map is written with its keys in sorted order, at every depth, the pretty text too" do
    # Atom and string keys sort by the string JSON carries; a struct is its own encoder's.
    term = %{"b" => 1, :a => %{"z" => [%{"y" => 1, "x" => 2}], "m" => nil}, "c" => true}
    assert BeamMCP.JSON.encode!(term) == ~s({"a":{"m":null,"z":[{"x":2,"y":1}]},"b":1,"c":true})
    # A key sorts by the text written for it: `nil` is written "nil", not "".
    assert BeamMCP.JSON.encode!(%{nil => 1, "a" => 2, "o" => 3}) == ~s({"a":2,"nil":1,"o":3})

    wide = Map.new(1..40, &{"k#{String.pad_leading(Integer.to_string(&1), 2, "0")}", &1})

    keys =
      Regex.scan(~r/"(k\d\d)"/, BeamMCP.JSON.encode!(wide, pretty: true), capture: :all_but_first)

    assert List.flatten(keys) == Enum.sort(Map.keys(wide))
  end
end
