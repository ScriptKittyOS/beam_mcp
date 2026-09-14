# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# The benchmark gate for the observed collector's per-call overhead.
#
#     mix run bench/overhead.exs            (N=100000 R=5 by default; env N, R override)
#
# Measures two postures over the same N `tools/call` messages through
# `BeamMCP.Server.handle_message/2`: (a) no collector started -- the span still emits, nobody
# listens -- and (b) the collector as shipped, the caller writing to its public ETS set.
# The figure is (b) minus (a) in microseconds per call, each the median of R rounds of N.
# Exits 1 when the figure is over the threshold, 0 otherwise, and prints one line either way.
#
# THE THRESHOLD IS A CEILING ON AN OPTIONAL, OFF-BY-DEFAULT FEATURE, NOT A PERFORMANCE PROMISE.
# It was set on 2026-09-14 against the measurements of that day (+0.55, +0.53, +0.71, +0.57,
# +0.71 us/call over a dispatch path of about 3.2 us, on 32 schedulers, OTP 28): roughly double
# the worst of them, so a noisy runner does not fail for no defect, while a change that makes
# the collector cost as much as the dispatch it watches -- the queue-per-event posture measured
# +1.69 -- is refused by number. The decision is the owner's; a later slice that needs it
# raised files a Question to the owner with the measurement attached. It is not an edit.
threshold_us = 1.5

n = String.to_integer(System.get_env("N", "100000"))
rounds = String.to_integer(System.get_env("R", "5"))

# A catalog of this script's own, so the gate needs no test-only fixture and no MIX_ENV.
defmodule BeamMCP.Bench.Catalog do
  @behaviour BeamMCP.Catalog

  @impl true
  def capabilities do
    %{
      tools: [
        %BeamMCP.ToolSpec{
          name: :echo,
          command_class: :read,
          mode: :read_only,
          description: "echo",
          input_schema: %{"type" => "object", "properties" => %{"k" => %{"type" => "string"}}}
        }
      ],
      resources: [],
      prompts: []
    }
  end
end

alias BeamMCP.Connectome.Observed
alias BeamMCP.Server

state =
  Server.new(
    dispatch: fn _, _, _ -> {:ok, %{"done" => true}} end,
    catalog: BeamMCP.Bench.Catalog,
    server_name: "bench"
  )

msg = %{
  "jsonrpc" => "2.0",
  "id" => 1,
  "method" => "tools/call",
  "params" => %{"name" => "echo", "arguments" => %{"k" => "v"}}
}

run = fn -> for _ <- 1..n, do: Server.handle_message(state, msg) end

median_us_per_call = fn ->
  times = for _ <- 1..rounds, do: :timer.tc(run) |> elem(0)
  med = times |> Enum.sort() |> Enum.at(div(rounds, 2))
  med / n
end

a = median_us_per_call.()
{:ok, collector} = Observed.start_link(name: :bench_overhead)
b = median_us_per_call.()
GenServer.stop(collector)

overhead = b - a

IO.puts(
  "collector overhead +#{Float.round(overhead, 3)} us/call " <>
    "(baseline #{Float.round(a, 3)}, shipped #{Float.round(b, 3)}; median of #{rounds} rounds of #{n}) " <>
    "threshold #{threshold_us}"
)

if overhead > threshold_us do
  IO.puts("BENCH FAIL: the collector's overhead is over the threshold")
  System.halt(1)
end
