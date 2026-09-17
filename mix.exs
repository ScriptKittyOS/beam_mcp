# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.MixProject do
  use Mix.Project

  @version "0.5.0"
  @source_url "https://github.com/ScriptKittyOS/beam_mcp"

  # The oldest OTP this project supports. Mix has an `elixir:` key but none for OTP, so the
  # floor is enforced here, at compile time: a below-floor build fails rather than shipping and
  # failing in a way that looks like a defect in this package. The reason travels with the
  # number (see `check_otp!/1` and the README), because a floor without a reason gets raised by
  # the next person who finds it inconvenient.
  @otp_floor 27

  @doc "The oldest OTP release this project supports."
  def otp_floor, do: @otp_floor

  @doc """
  Raises unless `release` -- the string `:erlang.system_info(:otp_release)` returns, or that
  form -- is at or above `otp_floor/0`. The message names the floor, the version found, and
  why the floor is where it is. Pure and public so a test can exercise the raise on any OTP.
  """
  def check_otp!(release) do
    found = release |> to_string() |> String.trim() |> Integer.parse()

    case found do
      {major, _rest} when major >= @otp_floor ->
        :ok

      {major, _rest} ->
        Mix.raise("""
        beam_mcp requires Erlang/OTP #{@otp_floor} or newer; found OTP #{major}.

        OTP 26.2 added the keyed process_info read the connectome tracer depends on --
        `:erlang.process_info(pid, {:dictionary, key})` reads one claim key without copying
        the whole process dictionary (2 us against up to a millisecond on a loaded tracer,
        measured) -- so OTP 26.2 is the hard requirement. The floor is set at #{@otp_floor}, one
        minor above it, because #{@otp_floor} is the oldest release this project supports: the
        release its CI matrix's lowest leg is to run the suite on, so that support is a
        measurement and not a hope. Today the suite is run on OTP 28, here and in CI. Older
        releases than #{@otp_floor} are neither tested nor supported.

        Install OTP #{@otp_floor} or newer (see .tool-versions), or pin an older beam_mcp.
        """)

      :error ->
        Mix.raise("beam_mcp could not read the OTP release from #{inspect(release)}")
    end
  end

  def project do
    _ = check_otp!(:erlang.system_info(:otp_release))

    [
      app: :beam_mcp,
      version: @version,
      # Fixtures under test/support compile only for the test environment: they are real
      # modules the connectome builder reads, never a mock, and they never ship.
      elixirc_paths: elixirc_paths(Mix.env()),
      # OTP 27 (the floor above) needs Elixir 1.17 or newer -- 1.15/1.16 do not run on it -- so
      # the two stated minimums are coherent: the oldest supported pair is Elixir 1.17 on OTP 27.
      elixir: "~> 1.17",
      elixirc_options: [warnings_as_errors: true],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      name: "BeamMCP",
      source_url: @source_url,
      docs: [
        main: "readme",
        extras: [
          "README.md",
          "CHANGELOG.md",
          "docs/connectome.md",
          "docs/connectome-canonical.md",
          "docs/connectome-observed.md",
          "docs/connectome-diff.md",
          "docs/connectome-reach.md",
          "docs/will-not-implement.md",
          "docs/threat-model.md",
          "docs/crypto-posture.md",
          "docs/fips.md"
        ],
        # Grouped by namespace, not by a list of names: a module added under either prefix
        # lands in its group without an edit here. The core modules are the ungrouped rest.
        groups_for_modules: [
          Transports: ~r/^BeamMCP\.Transport\./,
          Connectome: ~r/^BeamMCP\.Connectome\./
        ],
        groups_for_extras: [
          Connectome: ~r{^docs/connectome},
          Policy: ~r{^docs/(will-not-implement|threat-model|crypto-posture|fips)}
        ]
      ]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    # OTP's `tools` application carries `:xref`, which the declared-connectome builder reads
    # call edges with. Optional, in the one spelling Mix honours -- `tools: :optional` inside
    # extra_applications. A separate `optional_applications:` key is accepted by Mix and
    # ignored, and the first version of this line shipped tools as REQUIRED in the .app;
    # a test reads the .app the build writes. `crypto` is the digest's application, required:
    # through 0.5.0 it was absent here and an HTTP host had it only through plug and bandit,
    # both optional -- a stdio-only release would have had no :crypto.hash/2 at all.
    [extra_applications: [:logger, :crypto, tools: :optional]]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      # The dispatch path emits `[:beam_mcp, :dispatch, :start | :stop | :exception]` through
      # this, the ecosystem's emission point. Required, not optional: an optional emission would
      # branch the hot path on whether a module is loaded, and that second path is one nobody
      # exercises. Apache-2.0; no dependencies of its own.
      {:telemetry, "~> 1.0"},
      # Plug is the transport contract; Bandit is the server the host runs it on. Both are
      # optional: a host using only the stdio transport must not be made to pull an HTTP
      # server in, and `optional: true` keeps them out of that host's dependency tree.
      {:plug, "~> 1.16", optional: true},
      {:bandit, "~> 1.5", optional: true},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      # Property tests. Test-time only; it does not enter the published package.
      {:stream_data, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp description do
    "Model Context Protocol server core for the BEAM: protocol handling, stdio and stateless " <>
      "Streamable HTTP transports, and JSON Schema validation, with the tool catalog and " <>
      "dispatch injected by the host."
  end

  defp package do
    [
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib docs mix.exs README.md CHANGELOG.md LICENSE NOTICE LICENSES)
    ]
  end
end
