# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Fixture.Traced do
  @moduledoc false
  # A caller for the tracer tests, in the two shapes that matter to call tracing: a call
  # whose frame is kept (not in tail position) and one whose frame is dropped (tail
  # position). The BEAM's `{caller}` trace action names the frame it keeps, so a tail call
  # is attributed to the caller's caller. Kept out of the declared fixture's population.
  alias BeamMCP.Fixture.Declared.Beta

  def wrapped(x), do: {:ok, Beta.run(x)}
  def apply_wrapped(mod, args), do: {:ok, apply(mod, :run, args)}
  def tail(x), do: Beta.run(x)
end
