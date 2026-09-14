# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.PropertyRunsTest do
  # The gate's `properties` step prints the generation count it asked for; this property is
  # what makes that line a measurement. It counts its own generations and holds the count to
  # PROPERTY_RUNS when that is set (test/test_helper.exs reads it) and to StreamData's default
  # when it is not -- so a helper that stops reading the variable turns the step red rather
  # than leaving it printing a number nothing reached. A review lane showed the step green
  # over a neutralised helper before this file existed.
  use ExUnit.Case, async: true
  use ExUnitProperties

  property "the generations StreamData runs are the count PROPERTY_RUNS asked for, or the default" do
    expected =
      case System.get_env("PROPERTY_RUNS") do
        nil -> 100
        runs -> String.to_integer(runs)
      end

    assert Application.get_env(:stream_data, :max_runs) == expected

    counter = :counters.new(1, [])

    check all(_ <- constant(:ok)) do
      :counters.add(counter, 1, 1)
    end

    assert :counters.get(counter, 1) == expected
  end
end
