# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Fixture.Declared.Catalog do
  @moduledoc false
  # A catalog with two tools, one readable resource, one resource template (which the
  # declared builder cannot name -- a template has no uri), one readable prompt, and one
  # prompt entry no reader can name -- the builder must enumerate both, never drop either
  # silently.
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
      resources: [
        %BeamMCP.ResourceSpec{uri: "r://a", name: "a"},
        %BeamMCP.ResourceTemplateSpec{uri_template: "r://t/{x}", name: "t"}
      ],
      prompts: [%{name: "greet"}, :opaque]
    }
  end

  @impl true
  def read_resource(uri), do: {:ok, [%{uri: uri, text: "fixture"}]}
end
