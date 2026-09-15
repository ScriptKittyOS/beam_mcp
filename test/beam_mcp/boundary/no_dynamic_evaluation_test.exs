# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Boundary.NoDynamicEvaluationTest do
  # boundary: builds no name and evaluates no code at runtime
  # Every other census reads written names. This one holds that there is nothing else: no
  # `apply/2,3`, no `Code.eval_*`, `Code.compile_*`, `Code.require_file`, `Module.create`, and no
  # atom built from a binary -- with one allowance, the argument-key atoms `Server` builds from a
  # tool's declared schema properties (`String.to_atom(key)` over `Map.keys(properties)`), which
  # name arguments, never modules or functions. `Code.ensure_loaded?/1` and `ensure_compiled/1`
  # evaluate nothing and are not in the pattern.
  use ExUnit.Case, async: true
  alias BeamMCP.Boundary

  @dynamic ~r/\bapply\(|:erlang\.apply|Kernel\.apply|Code\.(eval\w*|compile\w*|require_file|string_to_quoted\w*)|Module\.create|List\.to_atom|List\.to_existing_atom|:erlang\.(binary_to_atom|list_to_atom|binary_to_existing_atom)|String\.to_existing_atom|String\.to_atom/
  @argument_keys ~r/^\|> Map\.new\(fn key -> \{key, String\.to_atom\(key\)\} end\)$/

  test "no line under lib/ evaluates code or builds a name at runtime, beyond the argument-key atoms" do
    hits =
      for {_, _, text} = hit <- Boundary.hits(@dynamic),
          not Regex.match?(@argument_keys, String.trim(text)),
          do: hit

    assert hits == [], "runtime evaluation under lib/:\n  " <> Boundary.format(hits)
    # The allowance is real: the argument-key line is there, and it is the only one.
    assert length(Boundary.hits(~r/String\.to_atom/)) == 1
  end
end
