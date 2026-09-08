<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Slice 007 — findings

## The three decisions, made deliberately

### (a) Where the hook runs: in `handle/2`, between `before_body/2` and `decode/2`

Two reasons, and the second is the load-bearing one.

It **must precede `Jason.decode`**, because the second argument is the bytes the client sent.

And it must **not** go inside `before_body/2`. That function is not a list of steps — it is the
*split* at the body read, and its `case` applies `close_after/1` to every refusal it produces. A
post-read hook placed there would inherit that closure and quietly falsify the invariant the
function's own comment states. `check_headers/3` is on the far side but runs *after* `decode/2`,
so it is too late. **Between the two is the only position that is both after the read and before
the parse.**

### (b) Status: `403` for a refusal, `500` for a raising hook

Identical to `authorize/1` at every point. Two hooks answering the same question with different
codes would make the status a hint about *which* check failed, and the contract for both is that
the caller learns nothing. A distinct code would be exactly the leak the opacity rule forbids.

### (c) No `connection: close` — the one place the answer differs from `authorize/1`

It differs because the fact underneath differs. A pre-read refusal answers over a body still on
the wire, so the adapter drains it on the server's behalf; that is what `close_after/1` declines.
Here the body is already read: the connection is clean and an ordinary response is possible.
`before_body/2`'s own comment pins the invariant —

> `decode/2` and everything after it are on the far side: the body is read by then, the
> connection is clean, and a refusal there keeps it. That is pinned in both directions.

Closing here would **break** that pin rather than honour it, and would cost a keep-alive
connection per refusal for nothing.

## The raw-bytes test, demonstrated red before it passed

A test never observed failing is not evidence. The call site was temporarily changed to hand the
hook `Jason.encode!(Jason.decode!(body))` — `logs/red-raw-bytes.txt`:

    1) test :authorize_body/2 — the post-read hook, and the bytes it is handed
       the hook receives the request body byte-identically, not a re-encoding
       code:  assert seen == @odd_body
       left:  "{\"id\":7,\"jsonrpc\":\"2.0\",\"method\":\"tools/call\",\"params\":{\"arguments\":{},\"name\":\"echo\"}}"
       right: "{\"jsonrpc\":\"2.0\" ,  \"method\":\"tools/call\",\n  \"params\":{\"name\":\"echo\",\"arguments\":{}}, \"id\":7}"

`left` is the round trip: keys sorted, padding gone, newline gone. `right` is what the client
sent. That is the whole defect a signature-verifying host would experience as broken crypto.

**The red took two unrelated tests with it, which was not predicted:**

    2) invalid JSON is a parse error          left: 500  right: 400
    3) an empty body is a parse error         left: 500  right: 400

`Jason.decode!` at the call site raises before `decode/2`'s error path can answer. So the
mutation is wrong for a second reason nobody stated in advance, and it is recorded rather than
tidied away.

Reverted, and the revert verified byte-identical against a pre-red copy rather than assumed.
`logs/green-raw-bytes.txt`: **`99 tests, 0 failures`, `TEST_EXIT=0`** for that file.

## Mutation scores — both KILL, zero variance

`tools/mutate.sh score Mab1 Mab2`, 2 passes, `logs/mutation-authorize-body.txt`:

    tree:    cb39add5b56542d0d743ce909bd49571396af7f2
    Mab1 | 172 tests, 5 failures TEST_EXIT=2 | 172 tests, 5 failures TEST_EXIT=2
    Mab2 | 172 tests, 5 failures TEST_EXIT=2 | 172 tests, 5 failures TEST_EXIT=2

**Mab1** removes the hook entirely — the call site *and* both clauses, because dropping only the
call would leave `authorize_body/3` unused and `--warnings-as-errors` would reject the build
before a test ran. That is a compiler kill, which records a kill that never happened. It kills
all five behavioural tests.

**Mab2** hands the hook a re-encoding. It kills the raw-bytes test plus four others, including
`HTTPBanditTest`'s live-listener check that a post-read refusal keeps the connection.

So the hook is not deletable without a red suite, and the raw-bytes guarantee is not removable
without a red suite. Those were the two things the mutants existed to establish.

## Two things found while doing this, neither predicted

**A README claim moved, and its test moved with it.** The paragraph asking *"Whether `authorize/1`
should instead run after the body is read … is an open design question … not something this
release settles"* is answered by this slice, so it is gone. `readme_claims_test.exs` pinned it
with `claims("open design question")` and went red — which is the convention working exactly as
written: *a test pinning a sentence nobody makes any more fails too*. It is **replaced**, not
deleted, by a pin on the sentence that settles the question. The two fragments about
`authorize/1`'s own limitation are untouched, because that limitation is still true of
`authorize/1` — the hook sits beside it rather than widening it.

**Three new claim fragments failed on the README's hard wrap.** `"authorize/1 keeps its position
before the body read"` spans a line break in the file. Each fragment is now checked against the
README with `grep` before being written into the test, and the test says so, because the next
person adding a claim will hit the same wall.

## Open, recorded rather than fixed

- **The hook cannot refuse *before* the body is buffered**, by construction — that is
  `authorize/1`'s job and the reason it keeps its position. A host wanting to avoid buffering
  for an unsigned request must reject on headers in `authorize/1` first. Stated because "add a
  signature check" invites the assumption that it also saves the read.
- **No test asserts the hook runs before `check_headers/3`.** Ordering against `decode/2` is
  pinned by the raw-bytes test; ordering against header validation is not, and a refactor could
  move it after `check_headers/3` without a red suite. It would still be before `Jason.decode`,
  so the raw-bytes guarantee holds — which is why this is recorded rather than blocking.

## The gate's own rule cost a change, and that is recorded rather than absorbed

Adding the arity check inline took `init/1` to a cyclomatic complexity of **11** against credo's
limit of **9**:

    [F] Function is too complex (cyclomatic complexity is 11, max is 9).
        lib/beam_mcp/transport/http.ex:145:9 #(BeamMCP.Transport.HTTP.init)

`CONVENTIONS.md`'s first rule — *"A non-zero count is a failure, not a number to hold"* — makes
that a real red rather than a threshold to adjust. The check is kept and extracted into
`validate_authorize_body!/1`, three clauses on the argument shape. Behaviour is identical: `nil`
through, a 2-arity function through, anything else the same `ArgumentError`.

**And the score above is the re-run, not the first one.** The first table was produced against
tree `0be739ce`; extracting the validator moved the tree, so it was scored again on `cb39add5`
and this record quotes the second. A score from a run on a different tree is not a score for this
one — the defect slice 002 round 7 found in a table headed "on the tree that ships".
