# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.ToolCatalog do
  @moduledoc """
  The contract a host implements to tell a `BeamMCP.Server` which tools exist.

  The server holds no catalog of its own. It advertises what `all/0` returns and accepts a
  `tools/call` only for a tool `all/0` names, so one implementation governs both — a tool
  advertised by `tools/list` and refused by `tools/call` is the defect this behaviour exists
  to make impossible.
  """

  @callback all() :: [BeamMCP.ToolSpec.t()]

  @doc """
  Finds the spec a tool name refers to, or `:error`.

  One lookup, used by every caller that has to answer "which tool does this name mean". The
  core uses it to decide whether a `tools/call` is callable at all; the HTTP transport uses it
  to read the `x-mcp-header` annotations it must validate against. Two implementations of this
  question would be two answers, which is precisely the header-versus-body disagreement the
  transport's validation exists to prevent.
  """
  @spec fetch(module(), String.t() | atom()) :: {:ok, BeamMCP.ToolSpec.t()} | :error
  def fetch(catalog, name) when is_atom(name), do: fetch(catalog, Atom.to_string(name))

  def fetch(catalog, name) when is_atom(catalog) and is_binary(name) do
    Enum.find_value(catalog.all(), :error, fn spec ->
      if Atom.to_string(spec.name) == name, do: {:ok, spec}
    end)
  end

  def fetch(_catalog, _name), do: :error
end
