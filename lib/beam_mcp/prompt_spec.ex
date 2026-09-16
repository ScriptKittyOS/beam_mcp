# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.PromptSpec do
  @moduledoc """
  A prompt a catalog offers: what `prompts/list` advertises and `prompts/get` renders.

  The fields are the `Prompt` object of the specification except `_meta`: `name` is required;
  `title`, `description`, `icons` and `arguments` (a list of `BeamMCP.PromptArgument`) are
  optional, the empty argument list the default, and `nil` fields are left off the wire.
  """

  alias BeamMCP.PromptArgument

  @enforce_keys [:name]
  defstruct [:name, :title, :description, :icons, arguments: []]

  @type t :: %__MODULE__{
          name: String.t(),
          title: String.t() | nil,
          description: String.t() | nil,
          icons: [map()] | nil,
          arguments: [PromptArgument.t()]
        }

  @doc """
  The JSON Schema a prompt's arguments are validated against -- the one the tools validator
  (`BeamMCP.Schema.validate/2`) runs, so a prompt argument and a tool argument go through
  one path. Every argument is a `string` property (the specification types `arguments` as
  an object of strings); `required` collects the flagged names; nothing undeclared is
  admitted, which is also what keeps a caller's key from ever becoming an atom.
  """
  @spec argument_schema(t()) :: map()
  def argument_schema(%__MODULE__{arguments: arguments}) do
    %{
      "type" => "object",
      "properties" => Map.new(arguments, &{&1.name, property(&1)}),
      "required" => for(%PromptArgument{required: true, name: name} <- arguments, do: name),
      "additionalProperties" => false
    }
  end

  defp property(%PromptArgument{description: nil}), do: %{"type" => "string"}
  defp property(%PromptArgument{description: d}), do: %{"type" => "string", "description" => d}
end
