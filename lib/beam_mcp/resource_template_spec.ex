# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.ResourceTemplateSpec do
  @moduledoc """
  A resource template a catalog offers: what `resources/templates/list` advertises, and the
  pattern a `resources/read` uri may match to be readable.

  The fields are the `ResourceTemplate` object of the specification except `_meta`:
  `uri_template` (RFC 6570) and `name` are required; the rest are optional and left off the
  wire when `nil`.
  The package matches a uri against a template at RFC 6570 level 1 plus reserved expansion:
  `{var}` matches one non-empty segment (no `/`), `{+var}` matches across segments; no other
  expression is claimed, and a template carrying one -- or a bare brace -- is refused by
  `BeamMCP.Catalog.validate/1`. It lives in the catalog's `resources:` list beside
  `BeamMCP.ResourceSpec` entries -- one list, two structs -- so the catalog contract gains no
  key.
  """

  @enforce_keys [:uri_template, :name]
  defstruct [:uri_template, :name, :title, :description, :mime_type, :annotations, :icons]

  @type t :: %__MODULE__{
          uri_template: String.t(),
          name: String.t(),
          title: String.t() | nil,
          description: String.t() | nil,
          mime_type: String.t() | nil,
          annotations: map() | nil,
          icons: [map()] | nil
        }
end
