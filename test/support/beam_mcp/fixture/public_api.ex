# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Fixture.PublicAPI do
  @moduledoc """
  A fixture for the public-API census: a documented module carrying every shape the
  population must see -- a plain function, one with default arguments, a hidden one, a
  deprecated one, a type, a callback -- beside a hidden sibling module. Nothing calls the
  deprecated function (the package compiles with warnings as errors). Test support only.
  """

  @typedoc "A type the census lists."
  @type shape :: :plain | :defaulted

  @doc "A callback the census lists."
  @callback render(term()) :: binary()

  @doc "A plain public function."
  @spec plain(term()) :: term()
  def plain(x), do: x

  @doc "Two default arguments: callable as defaulted/1, /2 and /3."
  @spec defaulted(term(), term(), term()) :: {term(), term(), term()}
  def defaulted(x, y \\ nil, z \\ nil), do: {x, y, z}

  @doc "Deprecated, with the replacement named."
  @deprecated "use plain/1"
  @spec old(term()) :: term()
  def old(x), do: plain(x)

  @doc "A macro the census lists."
  defmacro twice(x) do
    quote do
      {unquote(x), unquote(x)}
    end
  end

  @doc false
  def hidden(x), do: x
end

defmodule BeamMCP.Fixture.PublicAPI.Hidden do
  @moduledoc false
  # A public function in a hidden module: private surface, not an entry.
  def visible_in_the_beam(x), do: x
end
