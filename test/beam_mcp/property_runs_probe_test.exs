# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

# THE RED FOR THE PROPERTY GATE. This file exists in one commit only. It passes under
# StreamData's default of 100 generations and fails when the gate's run count reaches the
# generator -- so its failure is the proof that PROPERTY_RUNS is read, and the gate's
# `properties` step is shown red over it before it is shown green without it.
defmodule BeamMCP.PropertyRunsProbeTest do
  use ExUnit.Case, async: false
  use ExUnitProperties

  property "probe: the run count stays at StreamData's default (fails when the gate's count reaches the generator)" do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    check all(_ <- constant(:ok)) do
      Agent.update(counter, &(&1 + 1))
    end

    runs = Agent.get(counter, & &1)
    assert runs <= 100, "ran #{runs} generations: PROPERTY_RUNS reached the generator"
  end
end
