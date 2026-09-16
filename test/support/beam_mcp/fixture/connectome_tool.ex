# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Fixture.ConnectomeTool do
  @moduledoc false
  # The one tool a host that exposes tools only writes for the connectome surface, as
  # `BeamMCP.Connectome.Surface`'s moduledoc gives it. The package holds no tool (the
  # will-not-implement page's entry 11), so the spec lives on the host's side -- here, for
  # the tests that play the host.

  @spec spec() :: BeamMCP.ToolSpec.t()
  def spec do
    %BeamMCP.ToolSpec{
      name: :connectome,
      command_class: :observe,
      mode: :read_only,
      description: "Read a connectome graph as canonical JSON.",
      input_schema: %{
        "type" => "object",
        "properties" => %{
          "graph" => %{"type" => "string", "enum" => ["declared", "observed", "diff"]}
        },
        "required" => ["graph"],
        "additionalProperties" => false
      }
    }
  end
end
