# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Fixture.ObservedCatalog do
  @moduledoc false
  # A catalog for the collector's tests whose `echo` declares the keys the marker travels
  # under. A tool with no schema has its undeclared keys dropped before dispatch, so a
  # marker sent to it never reached the dispatch function -- a mutant that put the
  # arguments into the span's metadata survived the first marker tests, which is how that
  # vacuity was found. The tests now assert the dispatch saw the marker before asserting
  # the collector did not.
  def capabilities do
    %{
      tools: [
        %BeamMCP.ToolSpec{
          name: :echo,
          command_class: :observe,
          mode: :read_only,
          description: "Echo.",
          input_schema: %{
            "type" => "object",
            "properties" => %{
              "k" => %{"type" => "string"},
              "note" => %{"type" => "object"},
              "uri" => %{"type" => "string"}
            }
          }
        },
        %BeamMCP.ToolSpec{
          name: :write,
          command_class: :mutate,
          mode: :proposal,
          description: "Write."
        }
      ],
      resources: [],
      prompts: []
    }
  end
end
