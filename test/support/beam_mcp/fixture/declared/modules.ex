# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Fixture.Declared.MacroHelper do
  @moduledoc false
  # Called by MacroOnly's body at expansion time, and by nothing at runtime.
  def note(ast), do: ast
end

defmodule BeamMCP.Fixture.Declared.MacroOnly do
  @moduledoc false
  # Used by Alpha at compile time only. The expansion is arithmetic; no call to this module
  # survives into Alpha's beam, so the declared graph must show no edge from Alpha to it. The
  # macro's own body calls MacroHelper at expansion time: xref reports that from the
  # `MACRO-twice` function, and the builder must file it as an expansion call, not an edge.
  defmacro twice(x), do: BeamMCP.Fixture.Declared.MacroHelper.note(quote(do: unquote(x) * 2))
end

defmodule BeamMCP.Fixture.Declared.Outward do
  @moduledoc false
  # A runtime call to a module outside the scope, so the bound has a callee to enumerate. A
  # library function, not a BIF: calls to the runtime's built-ins are not reported (see the
  # builder's moduledoc), and `:erlang.monotonic_time/0` was measured to vanish for that reason.
  def now, do: :calendar.universal_time()
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
  # and arity. Measured: every one of the three arrives from xref as a `$M_EXPR` call -- the
  # variable-list `apply/3` with arity -1, xref's spelling of "arity unknown". None arrives as
  # a resolved call to `:erlang.apply/3`; a first draft of the builder looked for one.
  def call(mod, x), do: mod.run(x)
  def apply_to(mod, args), do: apply(mod, :run, args)
  def fun(f, x), do: f.(x)
end
