# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Boundary.NoOauthNoClientTest do
  # boundary: no OAuth in tree; no client library
  # The transport offers `authorize`/`authorize_body` hooks and performs no authorization of
  # its own: no OAuth flow, discovery document, token endpoint or bearer handling under lib/.
  # And the package is a server: no module under lib/ names itself a client, opens an outbound
  # connection, or sends an `initialize` request -- every `initialize` under lib/ is either a
  # clause head that receives one or the list of methods the modern era removed. A message
  # built with `"method" => "initialize"` anywhere else is a client, and fails here.
  use ExUnit.Case, async: true
  alias BeamMCP.Boundary

  @oauth ~r/oauth|authorization_server|token_endpoint|well-known|bearer|access_token|refresh_token/i
  @outbound ~r/:gen_tcp\.connect|:ssl\.connect|:httpc\.|Mint\.|Finch\.|Req\.(get|post|request)|HTTPoison|Tesla\./
  @client_module ~r/defmodule\s+\S*Client\b/

  test "no OAuth under lib/" do
    hits = Boundary.hits(@oauth)
    assert hits == [], "OAuth under lib/:\n  " <> Boundary.format(hits)
  end

  test "no client under lib/: no client module, no outbound connection, initialize only ever received" do
    hits = Boundary.hits(@outbound) ++ Boundary.hits(@client_module)
    assert hits == [], "a client under lib/:\n  " <> Boundary.format(hits)

    for {path, n, text} <- Boundary.hits(~r/"initialize"/) do
      assert text =~ ~r/def handle_message\(|@removed_in_modern/,
             "#{path}:#{n} names initialize other than as a received method: #{String.trim(text)}"
    end
  end
end
