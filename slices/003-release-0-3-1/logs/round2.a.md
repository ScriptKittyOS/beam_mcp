# Round 2, lane a — correctness and anchors, on the release commit

Tree read: `bae1fcaeb73b2146bf8b1ee49b79bd1bcd817988` (commit `8c296d8`). Pin: `round2.a.tree`.
Scope: the release commit's two new README-claim tests, plus a re-score of the anchors round 1
established, all on the tree that now ships.

**Verdict: no changes required.**

## The question this lane exists to answer

A README-claim test can be two things that look identical to a passing suite: an anchor, or a
quotation with an assertion stapled to it. The plan for this slice says each new claim gets a
test that quotes the sentence **and** exercises the behaviour, precisely because a quote-only pin
catches a sentence that moves and misses a sentence that becomes false. So the test is not read
and agreed with; it is scored.

| mutant | what it does | result | log |
|---|---|---|---|
| `Mr1` | `@annotatable_types` widened to admit `number`, `object`, `array` -- the (a) defect, restored | **KILLED** 158/4 | `mutation-r-Mr1.txt` |
| `Mr2` | uniqueness grouped by the original name, not the case-folded one -- the (b) defect, restored in the shape that looks most like a tidy-up | **KILLED** 158/3 | `mutation-r-Mr2.txt` |

`Mr1`'s four kills include **the new README-claim test itself**:

    1) test the HTTP transport's README claims a forbidden x-mcp-header annotation is the
       host's fault, as the README now says
    2) test ... an annotated `number` property is answered as a host fault, not as the caller's
       error
    3) test ... the refusal does not depend on the caller sending the header
    4) test ... an annotated `object` property is the same fault

So the claim is anchored by behaviour and not only by its own quotation. The second new claim --
the pre-read `connection: close` -- is anchored by `Md1` from round 1, which killed eight tests
including the Plug.Test header assertion the README test makes; it is not re-scored here because
nothing between the two rounds touched that path.

`Mr2` is worth naming as a shape rather than a mutant. Grouping by the original name instead of
the case-folded one is not a random perturbation; it is the edit a reader who has forgotten why
the fold is there would make while tidying, and it silently restores the defect the fold exists
to prevent. It dies on three tests.

## Read and accepted

- **`refute conn.resp_body =~ "number"` is a real assertion, not a tautology.** The refusal body
  is the constant `{"error":{"code":-32603,"message":"Internal error"},"id":1,"jsonrpc":"2.0"}`,
  and the diagnosis that *does* name `ratio`, `"number"` and `"Ratio"` goes to the log -- visible
  in the green run's captured output. If the detail were interpolated into the response instead,
  all three refutes fail. That is the "nothing about it reaches the caller" half, which a status
  check alone would miss.
- **`http_request/3` does not weaken `http_post_body/1`.** The size-sweep helper is left as it
  was, because the cap tests quote it and folding the two would make those read worse. Two
  helpers with two jobs, not one helper with a flag.
- **The version bump itself is not pinned by any test, and cannot honestly be.** No assertion can
  say "the version was raised in this commit" without hardcoding the version, which is the string
  grep `CONVENTIONS.md` says finds only what you already thought of. What *is* pinned is the
  relationship: `readme_claims_test.exs` derives the next break from `mix.exs` and refutes every
  requirement the README offers against it, so the pin and the version stay consistent whichever
  one moves.
