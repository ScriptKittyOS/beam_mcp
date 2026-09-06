# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.ToolSpec do
  @moduledoc """
  Typed MCP tool contract exposed to bounded agent runs.
  """

  @default_input_schema %{"type" => "object", "properties" => %{}, "additionalProperties" => true}

  @enforce_keys [:name, :command_class, :mode, :description]
  defstruct [
    :name,
    :command_class,
    :mode,
    :description,
    input_schema: @default_input_schema
  ]

  @typedoc """
  A JSON Schema object. The catalog supplies it; the server advertises it in `tools/list` and
  enforces it on `tools/call`. Defaults to an open object, which accepts anything -- a tool
  that wants a contract states one.
  """
  @type input_schema :: map()

  @type t :: %__MODULE__{
          name: atom(),
          command_class: atom(),
          mode: :read_only | :proposal,
          description: String.t(),
          input_schema: input_schema()
        }
end
