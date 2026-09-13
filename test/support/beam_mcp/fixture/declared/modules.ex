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
  alias BeamMCP.Fixture.Declared.Beta
  require BeamMCP.Fixture.Declared.MacroOnly, as: MacroOnly

  def run(x), do: Beta.run(MacroOnly.twice(x))
end

defmodule BeamMCP.Fixture.Declared.Gamma do
  @moduledoc false
  # Never called and calls nothing in scope: a node with no edges, which must still be a node.
  def lonely, do: :ok
end

defmodule BeamMCP.Fixture.Declared.Dyn do
  @moduledoc false
  # Three dynamic-dispatch sites, in the three shapes a host writes them. None resolves
  # statically; all must appear in the completeness bound, by the caller's module, function
  # and arity. `apply/3` with a literal argument list is inlined by the compiler into a
  # `$M_EXPR` call; with a variable list it stays a call to `:erlang.apply/3`, which xref
  # resolves -- so the builder must look for both.
  def call(mod, x), do: mod.run(x)
  def apply_to(mod, args), do: apply(mod, :run, args)
  def fun(f, x), do: f.(x)
end
