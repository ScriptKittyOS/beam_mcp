# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Wire.Recorder do
  @moduledoc """
  Records what the package puts on the wire for the advertising methods -- `server/discover`,
  `tools/list`, `resources/list`, `resources/templates/list`, `prompts/list` -- on the core
  (which is what stdio writes, one line per message) and through the HTTP transport, for one
  catalog. The recording is a map from the method to `%{"core" => the decoded response,
  "http" => the decoded HTTP body, "http_status" => the status}`, with nothing normalised: a
  change anywhere in a response is a change in the recording.

  Made so that a slice adding entries to a catalog can hold that every other byte on the
  wire stayed where it was: record before, record after, and the diff must be the entries.
  """

  alias BeamMCP.Server
  alias BeamMCP.Transport.HTTP

  import Plug.Test, only: [conn: 3]
  import Plug.Conn, only: [put_req_header: 3]

  @methods ~w(server/discover tools/list resources/list resources/templates/list prompts/list)
  @modern "2026-07-28"
  @meta %{
    "io.modelcontextprotocol/protocolVersion" => @modern,
    "io.modelcontextprotocol/clientCapabilities" => %{}
  }

  @spec record(module(), keyword()) :: %{String.t() => map()}
  def record(catalog, server_opts \\ []) do
    core = Server.new([catalog: catalog] ++ server_opts)

    http =
      HTTP.init(
        [
          catalog: catalog,
          dispatch: fn _, a, _ -> {:ok, a} end,
          authorize: fn _ -> :ok end,
          allowed_origins: :any
        ] ++
          server_opts
      )

    for method <- @methods, into: %{} do
      message = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => method,
        "params" => %{"_meta" => @meta}
      }

      {_, core_response} = Server.handle_message(core, message)

      conn =
        :post
        |> conn("/mcp", Jason.encode!(message))
        |> put_req_header("content-type", "application/json")
        |> put_req_header("mcp-protocol-version", @modern)
        |> put_req_header("mcp-method", method)
        |> HTTP.call(http)

      {method,
       %{
         "core" => core_response,
         "http" => Jason.decode!(conn.resp_body),
         "http_status" => conn.status
       }}
    end
  end
end
