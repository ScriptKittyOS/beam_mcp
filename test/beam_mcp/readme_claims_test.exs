# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.ReadmeClaimsTest do
  @moduledoc """
  The README claims listed here are pinned to the sentences they quote.

  `CONVENTIONS.md`: every claim listed in this file is pinned to the sentence it quotes; a claim
  not on the list is not pinned. That is the rule as it stands, and the narrower wording is the
  point -- an earlier version of both that rule and this moduledoc said *every* behavioural claim
  in the README was pinned, which promised a completeness no mechanism here delivers. Nothing
  enumerates the README's claims and proves each has a test.

  So this file catches a listed claim that **moves or disappears**. It does not catch a claim
  **added without a test**, nor one **contradicted by the prose around it** while the quoted
  fragment survives. Both gaps are demonstrated in `CONVENTIONS.md` rather than asserted.

  It is a separate file on purpose: a reader auditing the rule reads one file rather than
  grepping a suite, and a listed claim that loses its test loses it visibly.

  **Each test quotes the sentence it pins.** A claim whose quoted text no longer appears in the
  README is a claim that moved without its test, which is the failure the rule exists to catch.

  Written because a lane found the README recommending `{:beam_mcp, "~> 0.1"}` in the release
  that documents a wire break -- a requirement spanning both sides of it. That is a README
  claim about behaviour with nothing holding it, and it survived a version sweep because the
  stale string was not the version that changed.
  """
  use ExUnit.Case, async: true

  alias BeamMCP.Server
  alias BeamMCP.Transport.HTTP

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

  describe "what the package ships" do
    test "CHANGELOG.md is in the Hex files list" do
      # The red for this was asked of a built tarball, which proves the change. It does not
      # guard it: CHANGELOG.md could leave `files:` again and nothing would fail. r2's point,
      # and it is the difference between demonstrating a fix and pinning it.
      files = Mix.Project.config()[:package][:files]

      assert "CHANGELOG.md" in files,
             "the changelog is the only document explaining why a version changed, and " <>
               "without this it does not ship -- no release of this package before 0.2.1 " <>
               "contained it. Shipped files: #{inspect(files)}"
    end
  end

  describe "the dependency requirement the README hands a consumer" do
    test "it does not span the wire break this release documents" do
      requirement = "~> 0.3.0"
      claims("{:beam_mcp, \"#{requirement}\"}")

      version = Mix.Project.config()[:version]

      assert Version.match?(version, requirement),
             "the README's requirement must admit the version being shipped"

      refute Version.match?("0.1.0", requirement),
             "0.1.0 is on the far side of the documented removal of resultType and _meta " <>
               "serverInfo from legacy-declared results. A requirement admitting both sides " <>
               "carries a consumer across that break on a routine deps.update, which is what " <>
               "the minor bump was chosen to prevent."

      # The half that makes this durable. The assertion above pins the break that already
      # happened; on its own it passes unchanged through the next one, which is precisely
      # what it exists to prevent. So derive the next break from the policy -- breaks are at
      # the minor position while this package is 0.x -- rather than naming a version, and the
      # test keeps meaning the same thing for as long as that policy holds -- see the guard below.
      %Version{major: major, minor: minor} = Version.parse!(version)
      next_break = "#{major}.#{minor + 1}.0"

      if major == 0 do
        refute Version.match?(next_break, requirement),
               "the README recommends a requirement admitting #{next_break}, which is the next " <>
                 "minor and therefore the next documented wire break. That is the defect a " <>
                 "reviewer found in `~> 0.1` during 0.2.0, reproduced one release forward. " <>
                 "Demonstrated before this assertion existed: with the version set to the next " <>
                 "minor, this file passed green -- see slices/001c-dependency-pin/logs/red.txt."
      else
        # NOT an empty branch. An `if` whose else asserts nothing switches the test off rather
        # than switching policy, and a lane showed the consequence: at 1.0.0 with a README
        # recommending `>= 1.0.0` -- which admits 2.0.0 -- the suite went green and the test
        # named "it does not span the wire break" documented nothing, silently, on the day the
        # package reached 1.0. At 1.x a minor is compatible under semver, so the break moves to
        # the major; that is the assertion, and it is a real one.
        refute Version.match?("#{major + 1}.0.0", requirement),
               "at #{major}.x the documented break moves to the major version. The README " <>
                 "recommends a requirement admitting #{major + 1}.0.0."
      end

      # Guarded on major == 0 deliberately. The break-at-minor policy is a 0.x policy: under
      # semver proper a minor is a COMPATIBLE release, so at 1.x `~> 1.0` admitting 1.1.0 is
      # correct and refuting it would make this test demand a wrong requirement. An earlier
      # version of this assertion was unguarded, and the claim that it "keeps meaning the same
      # thing after every release" was false at 1.0.0 -- a lane demonstrated it rather than
      # arguing it. It keeps meaning the same thing for as long as the policy it encodes holds,
      # which is what an encoded policy can promise.
    end

    test "EVERY requirement the README offers excludes the next break" do
      # Derived, not blacklisted. The first version of this test refuted one literal spelling,
      # and a lane defeated it with three valid alternatives that never write that string --
      # `override: true` (the option list intervenes before the closing quote-brace), `>= 0.2.0`,
      # and `~>0.2` without the space -- all admitting the next minor, all green. That is a list
      # presented as a population, which is the defect this whole slice is about.
      #
      # So enumerate what the README actually offers and hold every one of them to the policy.
      # `[beam_mcp: "~> 0.2"]` is keyword-list sugar for `[{:beam_mcp, "~> 0.2"}]` -- the two
      # are the SAME Elixir term, so Mix cannot tell them apart, and a reader copying either
      # gets the same dependency. Both lanes evaded the first version of this scan with the
      # sugar, and with `{:"beam_mcp", …}` and `{:beam_mcp , …}`. A tuple-shaped pattern was a
      # narrower population than the thing it claimed to enumerate -- the same defect one level
      # down from the spelling blacklist it replaced.
      requirements =
        ~r/beam_mcp"?\s*[,:]\s*"([^"]+)"/
        |> Regex.scan(readme())
        |> Enum.map(fn [_full, req] -> req end)

      assert requirements != [], "the README must offer at least one dependency requirement"

      %Version{major: major, minor: minor} = Version.parse!(Mix.Project.config()[:version])

      for req <- requirements do
        # Widening the scan over prose means a captured string need not be a requirement at
        # all -- a JSON manifest line like `{ "beam_mcp": "^0.2.0" }` is caught by the same
        # pattern. Version.match?/2 would raise InvalidRequirementError with a stacktrace;
        # this turns that into a diagnosis. The red direction is safe either way, but a check
        # that crashes tells you less than one that says what it found.
        case Version.parse_requirement(req) do
          :error ->
            flunk(
              "the README offers `#{req}` where a version requirement is expected, and it is " <>
                "not a valid one. Either it is a requirement and it is malformed, or the scan " <>
                "matched something that is not a dependency at all -- the pattern reads prose, " <>
                "so both are possible and neither should pass silently."
            )

          {:ok, _} ->
            :ok
        end

        assert Version.match?(Mix.Project.config()[:version], req),
               "the README offers `#{req}`, which does not admit the version being shipped"

        if major == 0 do
          refute Version.match?("#{major}.#{minor + 1}.0", req),
                 "the README offers `#{req}`, which admits #{major}.#{minor + 1}.0 -- the next " <>
                   "minor, and therefore the next documented wire break while this package is " <>
                   "0.x. Every requirement the README hands a consumer must exclude it, not " <>
                   "just the one in the install snippet."
        else
          refute Version.match?("#{major + 1}.0.0", req),
                 "at 1.x and beyond a minor is a compatible release, so the break moves to the " <>
                   "major. The README offers `#{req}`, which admits #{major + 1}.0.0."
        end
      end
    end

    test "the paragraph explaining the tighter pin is still there" do
      # Acceptance criterion 4. The reasoning exists specifically so a future maintainer does
      # not tidy `~> 0.2.0` back to the Hex idiom, and a reason that can be deleted silently
      # does not survive the maintainer it was written for. A lane deleted the whole paragraph
      # and the suite stayed green.
      claims("not the more usual")
      claims("would carry you across the next such break")
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

  describe "the HTTP transport's README claims" do
    test "the numbers in the resource section are pinned to the sentences that state them" do
      # A round-3 lane measured every number in this section and found three wrong. None of them
      # was pinned -- the section was added without a single entry here -- and the three wrong
      # ones were the two-line claims, the kind that look too small to need a test.
      claims("caps a single body at 1 MiB")
      claims("about 1.05 MiB")
      claims("a partial of exactly")
      claims("constant across six socket-buffer settings and four runs")
      claims("num_acceptors * num_connections")
      claims("1,638,400")
      claims("15,000 ms under `Bandit`")
      claims("whole-body deadline rather than a per-read reset")
      claims("It does not bound **headers**")
    end

    test "the 1 MiB cap is the number the code enforces" do
      # The sentence and the constant are pinned to each other: 1,048,576 in and 200 out,
      # 1,048,577 in and 413 out. A cap that drifts from its documented value fails here rather
      # than in a host's logs.
      assert readme() =~ "caps a single body at 1 MiB"

      # Sized so the ENCODED REQUEST is exactly at the cap and exactly one byte over it, since
      # the cap is on the body the transport reads, not on the padding inside it.
      overhead = byte_size(request_body(""))

      assert http_post_body(String.duplicate("x", 1_048_576 - overhead)).status == 200
      assert http_post_body(String.duplicate("x", 1_048_576 - overhead + 1)).status == 413
    end

    test "arguments reach dispatch as atoms, as the README now says they do" do
      # Added in round 5. A release lane copied the README's catalog, wrote the obvious
      # `%{"place" => place}` clause in its dispatch, and got a silent no-match -- because keys
      # are atoms. The README said only "derived from the schema's properties", which is true and
      # does not tell a reader that. The claim is now explicit, so it is pinned.
      claims("reach\n`dispatch` as **atoms**")

      me = self()

      catalog = fn ->
        [
          %BeamMCP.ToolSpec{
            name: :get_weather,
            command_class: :observe,
            mode: :read_only,
            description: "Read the current weather for a place.",
            input_schema: %{
              "type" => "object",
              "properties" => %{"place" => %{"type" => "string"}},
              "required" => ["place"]
            }
          }
        ]
      end

      defmodule WeatherCatalog do
        @behaviour BeamMCP.ToolCatalog
        @impl true
        def all do
          Process.get(:catalog_fun).()
        end
      end

      Process.put(:catalog_fun, catalog)

      state =
        BeamMCP.Server.new(
          tool_catalog: WeatherCatalog,
          dispatch: fn _name, args, _opts ->
            send(me, {:dispatched, args})
            {:ok, args}
          end
        )

      BeamMCP.Server.handle_message(state, %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "tools/call",
        "params" => %{"name" => "get_weather", "arguments" => %{"place" => "Oslo"}}
      })

      assert_receive {:dispatched, %{place: "Oslo"}}
      refute_receive {:dispatched, %{"place" => _}}, 20
    end

    test "the server-side read before a refusal is the cap itself, not a range" do
      # The README said this number was "between 1.02 MiB and 1.50 MiB across socket-buffer
      # settings", attributed to the client's send buffer. Two quantities were being stated as
      # one. What the SERVER reads is `read_body/2`'s partial, and it is the cap exactly, at
      # every buffer size and on every run. What the CLIENT gets onto the wire before the
      # refusal arrives is neither in that range nor a function of the buffer -- measured 1.125
      # to 7.438 MiB, varying run to run at a fixed size -- so the README no longer quotes it as
      # a package property and this test pins the half that is one.
      #
      # That range read "1.4 to 7.4 MiB" until a lane checked it against the archive this same
      # commit added, where five of the 24 rows fall below 1.4. Counts are quoted from output,
      # never typed -- and this one was typed while the README beside it was correct.
      #
      # Pinned mechanically rather than by sentence alone, because the previous two drafts of
      # this line were both wrong and both survived a reader.
      conn =
        :post
        |> Plug.Test.conn("/mcp", String.duplicate("x", 3 * 1_048_576))
        |> Plug.Conn.put_req_header("content-type", "application/json")

      assert {:more, partial, _conn} = Plug.Conn.read_body(conn, length: 1_048_576)
      assert byte_size(partial) == 1_048_576

      # WHAT THIS ASSERTION DOES AND DOES NOT COVER, corrected after two lanes read it.
      #
      # It measures `Plug.Adapters.Test.Conn`, whose `read_body/2` is a `:binary.part` of an
      # in-memory binary and never consults `:read_length` at all. The README's number came from
      # BANDIT, against a real listener. So if Bandit's `read_body/2` started rounding up to
      # `:read_length`, the README would become false and this assertion would still pass.
      #
      # It is kept because it is not vacuous -- mutating the adapter to overshoot `:length` by
      # one read fails it, and mutating `@max_body_bytes` fails the transport assertion below --
      # but it pins the cap, not the adapter contract. The claim's real evidence is
      # `tools/measure_body.exs` and its archive; closing the gap needs a Bandit-backed test,
      # which is named in the slice record rather than implied here.
      assert readme() =~ "a partial of exactly"

      # And the documented number is the one the transport refuses on, so the sentence cannot
      # drift from @max_body_bytes without a failure here.
      conn = http_post_body(String.duplicate("x", 2 * 1_048_576))
      assert conn.status == 413
      assert Jason.decode!(conn.resp_body)["error"]["message"] =~ "1048576"
    end

    test "the implements/does-not-implement list matches what the transport does" do
      claims("=?base64?…?=` header values")
      claims("`Mcp-Param-{Name}`")
      claims("`404` with `-32601`")
      claims("no sessions, no `Mcp-Session-Id`, no SSE resumability")

      # The claim that the handshake is not implemented is the one a lane caught being false:
      # `initialize` returned 200 with the LEGACY protocol version while this sentence stood.
      assert readme() =~ "the `initialize` /"
      assert readme() =~ "refused** here rather than merely absent"

      # The core is dual-era and still serves these on stdio -- that is the README's point, and
      # the reason the refusal lives in the transport. Asserted so the sentence explaining the
      # split is pinned to a core that actually still answers them.
      state = Server.new(tool_catalog: Catalog, dispatch: fn _, a, _ -> {:ok, a} end)

      {_state, initialize} =
        Server.handle_message(state, %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "initialize"
        })

      assert initialize["result"]["protocolVersion"] == @legacy
    end

    test "the authorize/1 body limitation is stated with its measured failure mode" do
      claims("body-signature\nauthentication is not possible in `authorize/1`")
      claims("119 bytes `200`, 16 KiB and 200 KiB both `408`")
      claims("open design question")
    end
  end

  defp request_body(payload) do
    Jason.encode!(%{
      "jsonrpc" => "2.0",
      "id" => 1,
      "method" => "tools/call",
      "params" => %{"name" => "echo", "arguments" => %{"pad" => payload}}
    })
  end

  defp http_post_body(payload) do
    body = request_body(payload)

    :post
    |> Plug.Test.conn("/mcp", body)
    |> Plug.Conn.put_req_header("content-type", "application/json")
    |> Plug.Conn.put_req_header("mcp-protocol-version", @modern)
    |> Plug.Conn.put_req_header("mcp-method", "tools/call")
    |> Plug.Conn.put_req_header("mcp-name", "echo")
    |> HTTP.call(
      HTTP.init(
        tool_catalog: Catalog,
        dispatch: fn _n, a, _o -> {:ok, a} end,
        authorize: fn _conn -> :ok end,
        allowed_origins: :any
      )
    )
  end
end
