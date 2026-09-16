# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.PromptArgument do
  @moduledoc """
  One argument a prompt takes: the specification's PromptArgument object (its fields except
  `_meta`). `name` is required; `required` defaults to `false`; `description` and `title` are
  left off the wire when `nil`. A prompt's argument list is derived into the JSON Schema the
  tools validator runs (`BeamMCP.PromptSpec.argument_schema/1`), so an argument is validated
  the way a tool argument is.
  """

  @enforce_keys [:name]
  defstruct [:name, :description, :title, required: false]

  @type t :: %__MODULE__{
          name: String.t(),
          description: String.t() | nil,
          title: String.t() | nil,
          required: boolean()
        }
end
