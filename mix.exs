# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.MixProject do
  use Mix.Project

  @version "0.3.1"
  @source_url "https://github.com/ScriptKittyOS/beam_mcp"

  def project do
    [
      app: :beam_mcp,
      version: @version,
      # Fixtures under test/support compile only for the test environment: they are real
      # modules the connectome builder reads, never a mock, and they never ship.
      elixirc_paths: elixirc_paths(Mix.env()),
      elixir: "~> 1.15",
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
          "docs/connectome-canonical.md"
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
    # a test reads the .app the build writes.
    [extra_applications: [:logger, tools: :optional]]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
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
      files: ~w(lib mix.exs README.md CHANGELOG.md LICENSE NOTICE LICENSES)
    ]
  end
end
