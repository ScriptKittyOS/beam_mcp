# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Fixture.Declared.MacroOnly do
  @moduledoc false
  # Used by Alpha at compile time only. The expansion is arithmetic; no call to this module
  # survives into Alpha's beam, so the declared graph must show no edge from Alpha to it.
  defmacro twice(x), do: quote(do: unquote(x) * 2)
end

defmodule BeamMCP.Fixture.Declared.Beta do
  @moduledoc false
  def run(x), do: x
end

defmodule BeamMCP.Fixture.Declared.Alpha do
  @moduledoc false
  # The one known cross-module call in the fixture, plus a compile-time-only dependency.
  require BeamMCP.Fixture.Declared.MacroOnly, as: MacroOnly

  def run(x), do: BeamMCP.Fixture.Declared.Beta.run(MacroOnly.twice(x))
end

defmodule BeamMCP.Fixture.Declared.Gamma do
  @moduledoc false
  # Never called and calls nothing in scope: a node with no edges, which must still be a node.
  def lonely, do: :ok
end

defmodule BeamMCP.Fixture.Declared.Dyn do
  @moduledoc false
  # Two dynamic-dispatch sites. Neither resolves statically; both must appear in the
  # completeness bound, by the caller's module, function and arity.
  def call(mod, x), do: apply(mod, :run, [x])
  def fun(f, x), do: f.(x)
end
