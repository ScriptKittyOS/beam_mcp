# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.ReadmeClaimsTest do
  @moduledoc """
  Every behavioural claim the README makes about this package is pinned here.

  `CONVENTIONS.md`: the README states what the package does today, and every behavioural claim
  in it is pinned by a test that runs. This file is where that rule is discharged, and it is a
  separate file on purpose -- a reader auditing the rule can read one file rather than grepping
  a suite, and a claim that loses its test loses it visibly.

  **Each test quotes the sentence it pins.** A claim whose quoted text no longer appears in the
  README is a claim that moved without its test, which is the failure the rule exists to catch.

  Written because a lane found the README recommending `{:beam_mcp, "~> 0.1"}` in the release
  that documents a wire break -- a requirement spanning both sides of it. That is a README
  claim about behaviour with nothing holding it, and it survived a version sweep because the
  stale string was not the version that changed.
  """
  use ExUnit.Case, async: true

  alias BeamMCP.Server

  @modern "2026-07-28"
  @legacy "2025-11-25"
  @vkey "io.modelcontextprotocol/protocolVersion"

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

  # Dispatch that reports back, so "reaches execution" is observed rather than inferred.
  defp state do
    me = self()

    Server.new(
      tool_catalog: Catalog,
      dispatch: fn name, args, _opts ->
        send(me, {:dispatched, name})
        {:ok, args}
      end
    )
  end

  defp resp(msg), do: state() |> Server.handle_message(msg) |> elem(1)

  defp meta(method, version, extra \\ %{}) do
    Map.merge(
      %{"jsonrpc" => "2.0", "id" => 1, "method" => method, "_meta" => %{@vkey => version}},
      extra
    )
  end

  defp readme, do: File.read!(Path.join(__DIR__, "../../README.md"))

  # The claim text must still be in the README. A claim that moved without its test is the
  # thing the rule catches, so the quote is asserted rather than kept as a comment.
  defp claims(fragment) do
    assert readme() =~ fragment,
           "the README no longer contains the sentence this test pins:\n  #{fragment}\n" <>
             "Either the claim moved and this test must move with it, or the claim was " <>
             "deleted and so should this test. A test pinning a sentence nobody makes is " <>
             "worse than no test, because it reads as coverage."
  end

  describe "the dependency requirement the README hands a consumer" do
    test "it does not span the wire break this release documents" do
      claims(~s({:beam_mcp, "~> 0.2"}))

      version = Mix.Project.config()[:version]

      assert Version.match?(version, "~> 0.2"),
             "the README's requirement must admit the version being shipped"

      refute Version.match?("0.1.0", "~> 0.2"),
             "0.1.0 is on the far side of the documented removal of resultType and _meta " <>
               "serverInfo from legacy-declared results. A requirement admitting both sides " <>
               "carries a consumer across that break on a routine deps.update, which is what " <>
               "the minor bump was chosen to prevent."
    end
  end

  describe "the era table's ping and envelope rows" do
    test "ping is refused at 2026-07-28 and answered at 2025-11-25" do
      claims("| `ping` | removed from the revision, refused | answered |")

      assert resp(meta("ping", @modern))["error"]["code"] == -32_601
      assert resp(meta("ping", @legacy))["result"] == %{}
    end

    test "the result envelope follows the declared revision" do
      claims("| result envelope | `resultType` and `_meta` `serverInfo` |")

      modern = resp(meta("tools/list", @modern))["result"]
      assert modern["resultType"] == "complete"
      assert modern["_meta"]["io.modelcontextprotocol/serverInfo"]

      legacy = resp(meta("tools/list", @legacy))["result"]
      refute legacy["resultType"]
      refute legacy["_meta"]
    end
  end

  describe "the two exceptions the README names" do
    test "server/discover and initialize are matched before the switch and are undecorated" do
      claims("**neither result is decorated**")

      discover = resp(meta("server/discover", @modern))["result"]
      assert discover["protocolVersions"], "server/discover is answered whatever _meta says"

      refute discover["resultType"],
             "the README says a server/discover result carries no resultType even under " <>
               "2026-07-28, and calls that a known gap rather than a design choice"

      init =
        resp(meta("initialize", @modern, %{"params" => %{"protocolVersion" => @legacy}}))[
          "result"
        ]

      assert init["protocolVersion"] == @legacy
      refute init["resultType"]
    end
  end

  describe "the session is tracked, not enforced" do
    test "every method is served bare, tools/call included, and tools/call reaches dispatch" do
      claims("every method it implements is served bare, `tools/call`")

      bare = %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{"name" => "echo", "arguments" => %{}}
      }

      r = resp(bare)

      assert r["result"]["isError"] == false,
             "no initialize, no _meta, no session -- and it executes. This is the package's " <>
               "stated contract, not an accident, and the README says refusing unestablished " <>
               "callers is the host's job. Pinned so that neither adding nor removing that " <>
               "refusal can happen silently."

      assert_receive {:dispatched, :echo}
    end

    test "nothing in lib/ reads the initialized? flag" do
      claims("Nothing in this package refuses a request because")

      readers =
        "lib"
        |> Path.join("**/*.ex")
        |> Path.wildcard()
        |> Enum.flat_map(fn f -> File.read!(f) |> String.split("\n") end)
        |> Enum.filter(&String.contains?(&1, "initialized?"))
        |> Enum.reject(fn line ->
          # the typespec entry and the struct field are declarations, not reads
          String.contains?(line, "initialized?:") or String.contains?(line, "| initialized?")
        end)

      assert readers == [],
             "the README says the session is tracked and never enforced. These lines look " <>
               "like reads of the flag, which would make that claim false:\n" <>
               Enum.join(readers, "\n")
    end
  end

  describe "methods available at both eras" do
    test "tools/call and shutdown are served under either declared revision" do
      claims("`tools/call`, `shutdown`, `exit` at both eras")

      for version <- [@modern, @legacy] do
        call =
          meta("tools/call", version, %{
            "params" => %{"name" => "echo", "arguments" => %{}}
          })

        assert resp(call)["result"]["isError"] == false, "tools/call at #{version}"
        assert_receive {:dispatched, :echo}

        assert Server.shutdown?(
                 state()
                 |> Server.handle_message(meta("shutdown", version))
                 |> elem(0)
               ),
               "shutdown at #{version}"
      end
    end

    test "2024-11-05 is not supported and gets -32022" do
      claims("**`2024-11-05` is not supported**")

      r = resp(meta("tools/list", "2024-11-05"))
      assert r["error"]["code"] == -32_022
      assert r["error"]["data"]["supported"] == [@modern, @legacy]
    end
  end
end
