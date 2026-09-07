# Round 2, lane b — the shipped artefact as a consumer meets it

Tree read: `bae1fcaeb73b2146bf8b1ee49b79bd1bcd817988` (commit `8c296d8`). Pin: `round2.b.tree`.
Scope: `README.md`, `CHANGELOG.md`, `mix.exs`, `HANDOFF.md`, read as a consumer and as a reader
of the record rather than as a diff. Method: every quoted measurement checked against the log it
came from; every path checked for whether it resolves from where the file will be read.

**Verdict: changes required (three), and they are made.**

## Blocking

**B4. `HANDOFF.md` claimed a review that had not happened.** Its opening line read

> Two review rounds complete at the time this was written, with a third to close on the release
> commit itself.

One was complete. The second was this one, and it had not started when the sentence was written.
`CONVENTIONS.md` names a fabricated verification claim as the worst member of its family
specifically because it appears inside the artefact offered as proof, and a handoff is exactly
that artefact: it is the file the next reader trusts for how much review the work had.

**Fixed** by deleting the summary rather than correcting the number. The round table in
`FINDINGS.md` is written as each round closes and is now named as the answer, so there is one
place that can be right instead of two that can disagree.

**B5. The changelog cited slice records without saying they do not ship.** `CHANGELOG.md` is in
`mix.exs`'s `files:` and is an ex_doc extra, so it is read from inside the tarball and on
hexdocs, where `slices/003-release-0-3-1/…` resolves to nothing. Commit `a01e68d` fixed exactly
this for the previous release and established the form: the full repository-relative path plus a
statement that slice records are not shipped. The new section used the path and dropped the
statement.

**Fixed**, once for the section rather than once per reference.

**B6. A quoted table was abridged.** The changelog showed three columns of a six-column
measurement:

    requirement   0.3.0    0.3.1    0.4.0
    ~> 0.3.0      true     true     false

The numbers were right and the abridgement was in the flattering direction -- it dropped the
columns that do not bear on this release. `CONVENTIONS.md`'s derivation for the verbatim-archive
rule is a set of eight hand-copied verdicts of which **four were abridged**, and this is that
shape at small scale, in the file a consumer reads. **Fixed**: the whole row, all six columns, as
the run printed it, with the extract-versus-quotation distinction stated.

## Read and accepted

- **The README's version recommendation is right and does not move.** `~> 0.3.0` admits `0.3.1`
  and refuses `0.4.0`. Measured, not recalled. `readme_claims_test.exs` re-derives the next break
  from `mix.exs` at `0.3.1` and both requirement tests pass, so the policy is still encoded
  rather than restated.
- **`0.3.0`'s changelog section is not amended.** `git diff main..HEAD -- CHANGELOG.md` touches
  only the inserted `[0.3.1]` section.
- **`[0.3.1]` is headed `unreleased`**, which is correct until the owner dates it at tag time,
  and the handoff's release steps say so.
- **`HANDOFF.md` and `slices/` are not in `files:`**, so nothing repository-only ships.
- **No head hash in the handoff.** The previous one named `bdb032f` and went stale immediately,
  because a hash written into the file it describes cannot include the commit that writes it.
  The commits are listed by subject and `git log main..` is named as the authority. This is a
  small thing that has now cost two readers.

## Also checked, and true

- The changelog's count of pre-read refusal sites matches round 1's correction: six that did not
  close plus the `413` that did.
- The README's `8 MB` is the adapter's `8_000_000`-byte cap, which is 8 MB decimal, and the
  read-timeout claim resolves to the `15,000 ms under Bandit` already stated in the same section
  and already pinned by `claims("15,000 ms under `Bandit`")`.
- The new README paragraph on `x-mcp-header` states the no-declared-type carve-out, which is the
  scope limit the plan named and the code implements. Without it the paragraph would claim the
  transport judges every annotation, which it does not.
