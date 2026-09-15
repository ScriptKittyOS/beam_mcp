# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Boundary.NoInventedCapabilityTest do
  # boundary: claims no capability the specification does not define
  # The capabilities a server advertises -- in server/discover under 2026-07-28 and in the
  # initialize result under 2025-11-25 -- are held to the key sets the two schemas define for
  # `ServerCapabilities`. The sets are copied from the schema files, cited, because a test
  # cannot fetch them: `schema/2026-07-28/schema.json` and `schema/2025-11-25/schema.json` in
  # modelcontextprotocol/modelcontextprotocol, `$defs.ServerCapabilities.properties`, read
  # 2026-09-15 (2025-11-25 defines `tasks`; 2026-07-28 drops it and adds `extensions`). The
  # advertised map is a literal in `BeamMCP.Server` (one per era), so one catalog holds for every
  # catalog. Only `tools` is advertised today; the other sub-key sets are held against the
  # revision the day a capability is added.
  # An invented key -- a topology or reachability capability, say -- fails here.
  use ExUnit.Case, async: true
  alias BeamMCP.Server

  @schema_2026 ~w(completions experimental extensions logging prompts resources tools)
  @schema_2025 ~w(completions experimental logging prompts resources tasks tools)
  # The sub-keys each schema defines under a capability; `:open` where the schema lets the
  # server put anything there (`experimental`, `extensions`, and the empty `completions` and
  # `logging` objects).
  @subkeys_2026 %{
    "tools" => ~w(listChanged),
    "resources" => ~w(listChanged subscribe),
    "prompts" => ~w(listChanged),
    "completions" => :open,
    "logging" => :open,
    "experimental" => :open,
    "extensions" => :open
  }
  @subkeys_2025 %{
    "tools" => ~w(listChanged),
    "resources" => ~w(listChanged subscribe),
    "prompts" => ~w(listChanged),
    "tasks" => ~w(cancel list requests),
    "completions" => :open,
    "logging" => :open,
    "experimental" => :open
  }

  defmodule Catalog do
    @behaviour BeamMCP.Catalog
    @impl true
    def capabilities, do: %{tools: [], resources: [], prompts: []}
  end

  defp state, do: Server.new(catalog: Catalog)

  test "server/discover advertises only keys the 2026-07-28 schema defines" do
    {_, r} =
      Server.handle_message(state(), %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "server/discover"
      })

    caps = r["result"]["capabilities"]

    assert Map.keys(caps) -- @schema_2026 == [],
           "invented: #{inspect(Map.keys(caps) -- @schema_2026)}"

    assert invented_subkeys(caps, @subkeys_2026) == []
  end

  # Every sub-key under every advertised capability is one the schema defines for it.
  defp invented_subkeys(caps, subkeys) do
    for {key, value} <- caps,
        is_map(value),
        defined = Map.fetch!(subkeys, key),
        defined != :open,
        sub <- Map.keys(value) -- defined,
        do: {key, sub}
  end

  test "the initialize result advertises only keys the 2025-11-25 schema defines" do
    {_, r} =
      Server.handle_message(state(), %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "initialize",
        "params" => %{"protocolVersion" => "2025-11-25"}
      })

    caps = r["result"]["capabilities"]

    assert Map.keys(caps) -- @schema_2025 == [],
           "invented: #{inspect(Map.keys(caps) -- @schema_2025)}"

    assert invented_subkeys(caps, @subkeys_2025) == []
  end

  test "no line under lib/ names a topology or reachability capability on the wire" do
    hits = BeamMCP.Boundary.hits(~r/"(topology|reachability|connectome)"\s*=>/)
    assert hits == [], "a capability-shaped key under lib/:\n  " <> BeamMCP.Boundary.format(hits)
  end
end
