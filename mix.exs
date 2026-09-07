# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.MixProject do
  use Mix.Project

  @version "0.3.0"
  @source_url "https://github.com/ScriptKittyOS/beam_mcp"

  def project do
    [
      app: :beam_mcp,
      version: @version,
      elixir: "~> 1.15",
      elixirc_options: [warnings_as_errors: true],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      name: "BeamMCP",
      source_url: @source_url,
      docs: [main: "readme", extras: ["README.md", "CHANGELOG.md"]]
    ]
  end

  def application do
    [extra_applications: [:logger]]
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
      {:ex_doc, "~> 0.31", only: :dev, runtime: false}
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
