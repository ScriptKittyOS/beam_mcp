# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# The benchmark gate for the diff engine's cost on a 10 000-edge fixture.
#
#     mix run bench/diff.exs            (R=5 rounds by default; env R overrides)
#
# 501 nodes (a server and 500 tools) and up to 10 000 random edges per side over the four
# edge kinds, seeded, de-duplicated by key. Built the way bench/overhead.exs and bench/reach.exs
# are built: one untimed warm-up of each operation, then R timed rounds, the MEDIAN reported --
# `Diff.run/3` and `Diff.encode!/1` measured and judged SEPARATELY, because they are two
# programs (a set computation over edge keys; a canonical encoder over the record) and a
# regression in one is not a regression in the other. Prints one line; exits 1 when either
# median is over its threshold, 0 otherwise.
#
# THE THRESHOLDS ARE CEILINGS ON A COST NO CONSUMER PAYS ON THE WIRE UNLESS IT ASKS FOR A DIFF,
# NOT A PERFORMANCE PROMISE. Until this release the diff was recorded and not judged: the first
# script here was a one-shot with no warm-up whose figures moved ~35 % run to run (112-152 ms
# on one machine in one day), and a ceiling against that would have caught nothing or cried
# wolf. Measured with a warm-up and the median of five instead, the figures settle -- but the
# encoder's figure depends on the HEAP HISTORY of the process that runs it (measured 2026-09-16
# on this fixture, one machine, 32 schedulers, OTP 28): 115-126 ms in a fresh process; 133-151
# ms in a process that had already encoded once; 240-252 ms in a process still holding six diff
# records from earlier rounds -- the benchmark's own garbage raising the encoder's GC cost, not
# a cost a consumer's request pays. So every timed round here runs in a FRESH PROCESS (a Task),
# and the figure is the operation's alone. Ten runs of this script on the release head, so
# measured: run 117.9-121.6 ms, encode 121.1-130.1 ms. The owner's rule sets each ceiling at roughly
# DOUBLE the stable worst of those runs -- 121.6 -> 245, 130.1 -> 260 -- so a noisy runner does
# not fail for no defect while a change that doubles the cost of either program is refused by
# number. (Shown red first with both constants below the measurement: run 118.54 over 60,
# encode 124.05 over 70, the gate's bench step FAIL; then restored to these, the gate green.) The decision is the
# owner's (2026-09-15, the revisit condition of the 0.4.0 decision to leave the diff recording:
# reachability landed and graph cost became something a consumer feels); a later slice that
# needs either raised files a Question to the owner with the measurement attached. It is not an
# edit.
threshold_run_ms = 245
threshold_encode_ms = 260

alias BeamMCP.Connectome.{Diff, Edge, Graph, Node}

rounds = String.to_integer(System.get_env("R", "5"))

server = "bench"
srv = Node.new!(kind: :server, level: :server, identity: {:server, server})

tools =
  for i <- 1..500, do: Node.new!(kind: :tool, level: :server, identity: {:tool, server, :"t#{i}"})

id = fn i -> Node.id({:tool, server, :"t#{i}"}) end

edges = fn provenance, seed ->
  :rand.seed(:exsss, seed)

  for _ <- 1..10_000 do
    Edge.new!(
      from: id.(:rand.uniform(500)),
      to: id.(:rand.uniform(500)),
      kind: Enum.random([:invoke, :read, :message, :supervise]),
      provenance: provenance
    )
  end
  |> Enum.uniq_by(&Edge.key/1)
end

declared =
  Graph.new!(
    schema_version: Graph.schema_version(),
    nodes: [srv | tools],
    edges: edges.(:declared, {1, 2, 3})
  )

observed =
  Graph.new!(
    schema_version: Graph.schema_version(),
    nodes: [srv | tools],
    edges: edges.(:observed, {1, 2, 4})
  )

window = %{"started_at" => "2026-09-14T00:00:00Z", "ended_at" => "2026-09-14T01:00:00Z"}

# One warm-up, then the median of R, each in a fresh process so the figure does not depend on
# what earlier rounds left on the heap (see above). The operation's own result comes back with
# the figure so the encoder is timed over a record this run produced.
median_ms = fn run ->
  fresh = fn -> Task.async(fn -> :timer.tc(run) end) |> Task.await(:infinity) end
  {_, {:ok, _}} = fresh.()
  timed = for _ <- 1..rounds, do: fresh.()
  {med_us, {:ok, value}} = timed |> Enum.sort_by(&elem(&1, 0)) |> Enum.at(div(rounds, 2))
  {Float.round(med_us / 1000, 2), value}
end

{run_ms, diff} = median_ms.(fn -> Diff.run(declared, observed, window: window) end)
{encode_ms, bytes} = median_ms.(fn -> {:ok, Diff.encode!(diff)} end)

IO.puts(
  "diff #{length(declared.edges)}/#{length(observed.edges)} edges: run #{run_ms} ms, " <>
    "encode #{encode_ms} ms (medians of #{rounds} after a warm-up; record #{byte_size(bytes)} B) " <>
    "thresholds run #{threshold_run_ms}, encode #{threshold_encode_ms}"
)

over =
  Enum.reject(
    [{"run", run_ms, threshold_run_ms}, {"encode", encode_ms, threshold_encode_ms}],
    fn {_, ms, threshold} -> ms <= threshold end
  )

if over != [] do
  for {name, ms, threshold} <- over do
    IO.puts(
      "BENCH FAIL: the diff's #{name} median #{ms} ms is over its threshold #{threshold} ms"
    )
  end

  System.halt(1)
end
