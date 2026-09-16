# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Boundary.NoMrtrTest do
  # boundary: runs no multi-round-trip request
  # 2026-07-28 lets a server answer `tools/call`, `resources/read` and `prompts/get` with an
  # `InputRequiredResult` and continue on a later request carrying `inputResponses` and
  # `requestState`. This package answers every request completely or refuses it: the one
  # `resultType` written under `lib/` is `"complete"`, at one site, and neither continuation
  # parameter is read anywhere -- a request carrying them is served as if it carried neither,
  # because the package never asked for input. Stated on the will-not-implement page with its
  # reason; this census is what holds it.
  use ExUnit.Case, async: true
  alias BeamMCP.Boundary

  test "the only resultType written under lib/ is complete, at one site" do
    hits = Boundary.hits(~r/"resultType"/)
    assert length(hits) == 1, "resultType sites under lib/:\n  " <> Boundary.format(hits)
    assert [{_, _, line}] = hits
    assert line =~ ~s("resultType", "complete")
  end

  # The one place the names appear under lib/ is the sentence in BeamMCP.Server's moduledoc
  # that says they are not read, permitted by its exact text: a doc line is not a read, and
  # the refusal is written down by name where a maintainer meets it.
  @stated [
    "`InputRequiredResult` and continue on a later request carrying `inputResponses` and a",
    "`requestState`. This core does not: every request is answered completely or refused, the"
  ]

  test "no line under lib/ reads inputResponses or requestState, and none names InputRequiredResult" do
    hits =
      for {_, _, text} = hit <-
            Boundary.hits(
              ~r/inputResponses|requestState|InputRequired|input_required|input_responses|request_state/
            ),
          String.trim(text) not in @stated,
          do: hit

    assert hits == [],
           "a continuation parameter or result under lib/:\n  " <> Boundary.format(hits)

    # The allowance is real: both stated lines are there.
    assert length(Boundary.hits(~r/InputRequiredResult|requestState/)) == 2
  end
end
