# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.ResourceSpec do
  @moduledoc """
  A resource a catalog offers: what `resources/list` advertises and `resources/read` may read.

  The fields are the `Resource` object of the specification, in this package's spelling:
  `uri` and `name` are required; the rest are optional and, when `nil`, are left off the
  wire rather than sent as `null`. `annotations` and `icons` are passed through as the host
  gives them (maps and lists the specification defines; the package does not read them).
  """

  @enforce_keys [:uri, :name]
  defstruct [:uri, :name, :title, :description, :mime_type, :size, :annotations, :icons]

  @type t :: %__MODULE__{
          uri: String.t(),
          name: String.t(),
          title: String.t() | nil,
          description: String.t() | nil,
          mime_type: String.t() | nil,
          size: non_neg_integer() | nil,
          annotations: map() | nil,
          icons: [map()] | nil
        }
end
