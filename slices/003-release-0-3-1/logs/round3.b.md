# Round 3, lane b — the record against the tree it describes

Tree read: `c504d36db97a22bc745c157c7d2e68e3d98479a4` (commit `11e0b7a`). Pin: `round3.b.tree`.
Scope: every count written into a code comment, a test comment, a commit message or a slice log,
checked against the tree that ships rather than the tree it was written on.

**Verdict: changes required (one), and it is made.**

## Blocking

**C2. Two comments carried counts from the tree they were written on, not the tree that ships.**

This is slice 002 round 7's blocker exactly — a mutation result labelled for a tree it was not
scored on — and it had reappeared in two places written by this slice:

- `lib/beam_mcp/transport/http.ex`, `tool_annotations/2`: "the mutant that leaves it outside
  SURVIVES the suite (… 156 tests, 0 failures)". True when written. The shipping tree is 158.
- `test/beam_mcp/transport/http_test.exs`, the deleted-stand-in block: `ALWAYS re-raises ->
  KILLED, 147 tests, 1 failure` and `NEVER re-raises -> SURVIVES, 147 tests, 0 failures`. Both
  true when written, at 147. The shipping tree is 158.

Nothing about the *verdicts* was wrong: all three still hold. That is what makes this the
dangerous version of the defect rather than the obvious one — the number is the only thing that
is false, and a reader who re-runs the mutant and gets a different total has to work out whether
the verdict moved with it.

**Fixed**: both now cite `slices/003-release-0-3-1/logs/mutation-round3.txt`, the table produced
on the final tree and run twice, and quote 158.

## Read and accepted

- **`round1.a.md`'s table still shows 147 and 156, and is left alone.** A round verdict is a
  record of what that round measured against the tree it pinned; rewriting it to match a later
  tree would be the corrections-are-appended rule broken in the file that exists to hold the
  correction. `FINDINGS.md` carries the re-score and says which table is which.
- **The (c) and (d) commit messages likewise keep their original counts.** Same reason. The
  round-3 re-score is recorded, not backfilled.
- **`CHANGELOG.md` and `README.md` quote no mutation counts**, so nothing shipped to a consumer
  needed re-pointing.
- **`HANDOFF.md`'s `158 tests, 0 failures` and `25 commentable files` match the final gate**,
  `logs/gate-round3.txt`.
- **The version measurement quoted in `CHANGELOG.md` is the whole row**, corrected in round 2,
  and still matches `logs/measure-version-requirement.txt` byte for byte on that row.
- **`logs/probe-d-large-body-reset.txt` is captured whole.** Its first capture was piped through
  `grep -v` to hide a repeated log line, which is not a verbatim archive; it was re-run and
  written whole before this verdict was signed.
