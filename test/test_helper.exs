# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

# A hot reload of a module replaces the beam `mix test --cover` instrumented, and cover then
# cannot collect that module at all (measured: `Observed` and `Tracer` vanished from the table
# once the reload tests landed). Under cover those tests are excluded -- the gate runs the
# plain suite, where they run -- so the coverage record keeps the modules they reload.
cover? = Code.ensure_loaded?(:cover) and :cover.modules() != []
ExUnit.start(exclude: if(cover?, do: [:hot_reload], else: []))

# The gate's `properties` step runs the property tests alone at a generation count it sets
# through PROPERTY_RUNS (tools/gate.sh); the plain suite keeps StreamData's default of 100.
# Read here rather than from a config file: the package ships no config/, and what this suite
# proves must not depend on a consumer's. A value that is not a positive integer is refused by
# name, not silently taken as the default.
case System.get_env("PROPERTY_RUNS") do
  nil ->
    :ok

  runs ->
    case Integer.parse(runs) do
      {n, ""} when n > 0 -> Application.put_env(:stream_data, :max_runs, n)
      _ -> raise ArgumentError, "PROPERTY_RUNS must be a positive integer, got: #{inspect(runs)}"
    end
end
