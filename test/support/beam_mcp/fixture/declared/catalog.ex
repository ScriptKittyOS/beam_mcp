# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Fixture.Declared.Catalog do
  @moduledoc false
  # A catalog with two tools, one readable resource, one readable prompt, and one resource
  # entry no reader can name -- the builder must enumerate it, never drop it silently.
  @behaviour BeamMCP.Catalog

  @impl true
  def capabilities do
    %{
      tools: [
        %BeamMCP.ToolSpec{
          name: :echo,
          command_class: :observe,
          mode: :read_only,
          description: "Echo."
        },
        %BeamMCP.ToolSpec{
          name: :write,
          command_class: :mutate,
          mode: :proposal,
          description: "Write."
        }
      ],
      resources: [%{uri: "r://a"}, :opaque],
      prompts: [%{name: "greet"}]
    }
  end
end
