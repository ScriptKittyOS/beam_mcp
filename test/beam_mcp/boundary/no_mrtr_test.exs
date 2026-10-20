# SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
# SPDX-License-Identifier: Apache-2.0

defmodule BeamMCP.Boundary.NoMrtrTest do
  # boundary: runs no multi-round-trip request
  # 2026-07-28 lets a server answer `tools/call`, `resources/read` and `prompts/get` with an
  # `InputRequiredResult` and continue on a later request carrying `inputResponses` and
  # `requestState`. This package answers every request completely or refuses it: no
  # `resultType` written under `lib/` is `"input_required"` (each is a literal, so the census
  # can read it), and neither continuation parameter is read anywhere -- a request carrying
  # them is served as if it carried neither, because the package never asked for input. The
  # line is drawn at `input_required`, not at "only `complete`", so that another result type
  # the specification defines (the Tasks extension's `"task"`, SEP-2663) can be added without
  # crossing it. Stated on the will-not-implement page with its reason; this census holds it.
  use ExUnit.Case, async: true
  alias BeamMCP.Boundary

  test "every resultType written under lib/ is a literal, and none is input_required" do
    hits = Boundary.hits(~r/"resultType"/)
    assert hits != [], "no resultType site under lib/: the census reads nothing"

    for {_, _, line} = hit <- hits do
      assert [_, value] = Regex.run(~r/"resultType",\s*"([a-z_]+)"/, line),
             "a resultType that is not a literal, which this census cannot read:\n  " <>
               Boundary.format([hit])

      refute value == "input_required", "an input_required result:\n  " <> Boundary.format([hit])
    end
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
