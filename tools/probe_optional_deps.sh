#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0
#
# The package must compile for a consumer that does not have `plug`.
#
# `optional: true` governs dependency RESOLUTION, not compilation: the module still compiles
# in this tree, where plug is present, and fails in the consumer's, where it is not. Round 1
# found exactly that -- an unconditional `import Plug.Conn` broke every stdio-only host -- and
# nothing in the gate would have caught it coming back.
#
# It builds a throwaway consumer project outside the tree that depends on beam_mcp by path and
# on nothing else, and ASSERTS ON THE ARTEFACT: BeamMCP.Server's beam must exist and
# BeamMCP.Transport.HTTP's must not. An exit code alone is not enough -- the first version of
# this probe read `head`'s status rather than `mix compile`'s and reported success.
set -uo pipefail
root=$(git rev-parse --show-toplevel) || exit 1
work=$(mktemp -d) || exit 1
trap 'rm -rf "$work"' EXIT

mkdir -p "$work/lib"
cat > "$work/mix.exs" <<MIXEOF
defmodule OptionalDepProbe.MixProject do
  use Mix.Project
  def project, do: [app: :optional_dep_probe, version: "0.0.1", elixir: "~> 1.16", deps: deps()]
  def application, do: [extra_applications: [:logger]]
  defp deps, do: [{:beam_mcp, path: "$root"}]
end
MIXEOF

cd "$work" || exit 1
out=$(mix deps.get 2>&1 && mix compile --force 2>&1); rc=$?
ebin="$work/_build/dev/lib/beam_mcp/ebin"

if [ "$rc" -ne 0 ]; then
  echo "FAIL: a consumer without plug cannot compile beam_mcp (exit $rc)"
  printf '%s\n' "$out" | sed 's/^/    /'
  exit 1
fi
if [ -d "$work/deps/plug" ]; then
  echo "FAIL: plug was fetched into a consumer that never asked for it -- it is not optional"
  exit 1
fi
if [ ! -f "$ebin/Elixir.BeamMCP.Server.beam" ]; then
  echo "FAIL: compile reported success but BeamMCP.Server.beam does not exist"
  exit 1
fi
if [ -f "$ebin/Elixir.BeamMCP.Transport.HTTP.beam" ]; then
  echo "FAIL: BeamMCP.Transport.HTTP compiled without plug present -- the guard is not working"
  exit 1
fi
echo "pass: consumer compiles without plug; Server present, Transport.HTTP absent"
