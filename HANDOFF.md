# HANDOFF — beam_mcp, slice 002 (stateless Streamable HTTP)

Stopped mid-round-4 at the owner's request, after a session rate limit killed two of the three
lanes. Nothing is tagged, nothing is published.

## State

- Branch `slice/002-streamable-http`, HEAD **`68e113e`**, tree **`89f7a25`**.
- Gate green at HEAD: format, compile, **126 tests**, credo, optional-deps probe, reuse, licences.
- Working tree clean except the round-4 lane artefacts, which this commit adds.
- Version `0.3.0`, unreleased. `0.2.0` is published and is not amended.

## Round 4 — incomplete, and it found three publish blockers before it stopped

Three lanes launched on tree `89f7a25` (scope: `git diff ebaaed0 HEAD`). All three recorded that
tree hash, so all three read the same bytes.

- **s1 — completed. VERDICT: changes required. Three findings BLOCK PUBLISH, three FILE.**
  Report: `slices/002-streamable-http/logs/round4.s1.md`.
- **r1 — killed by the rate limit** after writing only `round4.r1.tree`. No report. Its brief was
  the mutant 14–23 re-run and the new tests' honesty. **Re-run it.**
- **r2 — killed by the rate limit** after writing `round4.r2.tree` and one partial result, below.
  Its brief was release readiness: tarball, docs warnings, and the README example run verbatim.
  **Re-run it — no lane has yet read the shipped artefact as a package rather than as a diff.**

### The three blockers (all in the round-3 fixes, all measured against `ebaaed0`)

1. **`value_matches?/2` crashes on an attacker-chosen integer** — `http.ex:414-419`. An
   unauthenticated `500` with an error-level stacktrace where the pre-delta code returned `400`.
2. **`value_matches?/2` accepts a *different* integer** — same function. `Float.parse(h) == body * 1.0`
   compares IEEE-754 doubles, and above 2^53 that map is not injective, so distinct integers
   collide. `Mcp-Param-{Name}` stops preventing the header/body disagreement it exists for.
   Pre-delta `400`, now `200` and dispatched.
3. **`fault_response/4` is right for `call/2` and wrong for `dispatch/3`** — `http.ex:249-256`,
   reached from `:663`. It re-raises an exception a *host tool* raised, escaping the JSON-RPC
   envelope. The status-aware rule belongs on the adapter's own exceptions, not on the host's.

Filed, not blocking: colliding `x-mcp-header` names collapse silently (F4); an annotation on a
non-primitive property makes a tool permanently uncallable with no explanation (F5);
`ToolCatalog.fetch/2`'s `@spec` is not honest now that it is public API (F6).

**s1 confirms the three things it was asked to verify by exploit are fixed and holding:** Base64
decoding is correctly scoped to `Mcp-Name`/`Mcp-Param-*`, the omitted-header MUST is enforced, and
the second rescue copy does reach `fault_response/4`. Finding 3 is that third fix applied to the
copy it does not fit.

### One partial measurement from r2, which contradicts a line I wrote

r2 reported, before dying: **the server-side read before refusal is a constant 1,048,576 bytes,
not a range.** `README.md` currently says 1.02–1.50 MiB and attributes the spread to the client's
socket buffer. That sentence was already corrected once this slice — it began as a single exact
byte count a lane could not reproduce. **Do not fix it from this note.** Re-measure it, decide
whether the number is a server property or a client artefact, and pin whatever survives in
`readme_claims_test.exs`.

## Next steps, in order

1. Fix the three blockers. Blockers 1 and 2 are one function; write the integer comparison so it
   is exact (compare integers as integers, and treat a header that is not an exact integer literal
   as a non-match) rather than routing through floats.
2. Re-run lanes r1 and r2 on the resulting tree. s1 does not need re-running unless the fixes
   touch what it cleared.
3. Settle the read-before-refusal number and pin it.
4. Then, and only then, the slice closes. **Tag and publish are owner steps** — never
   `mix hex.publish`, never push a tag.

## Standing context

The base rate is the reason rounds keep being justified, not caution: round 2's blockers were both
reintroductions of shapes fixed in the same commit; two of round 3's three highest were regressions
caused by round 2's fixes; and round 4 has now found three more in round 3's fixes. Every round so
far has found a regression introduced by the previous round's fixes. `slices/002-streamable-http/FINDINGS.md`
carries that table and the attributions.

Evidence lives in `slices/002-streamable-http/logs/`: `mutation.md` (23 mutants across three
rounds, with two corrections to its own earlier claims), `round{1,2,3}.*.md`, `round4.s1.md`, and
the gate captures.
