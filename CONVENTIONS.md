<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Conventions

How this package is developed. Short, and each entry exists because something went wrong once.

## The gate takes no baseline

`--strict` means what it says. There is no ratchet file, no tolerated count, and no generated
`.credo.exs` — credo runs on its own defaults so that a check cannot be switched off in a
config nobody reads. A non-zero count is a failure, not a number to hold.

This is deliberate and it is the opposite of the tree this package was extracted from, which
carries recorded baselines for accumulated debt. Not carrying another tree's tolerances is
most of the reason the package exists.

## A probe's population must be derived the way the checked mechanism derives it

A probe that plants a violation the check **cannot see** proves nothing, and it proves nothing
quietly: the step reports `pass`.

Measured, twice in one day:

1. **This package's REUSE check.** The probe wrote an unheadered file and never `git add`ed it.
   The check derives its population from `git ls-files`, so the file was invisible. The gate
   failed for an unrelated reason while the `reuse` line read `pass`. Adding the file first
   turns it genuinely red.
2. **The sibling tree's link check.** Its source enumeration had no probe that could fail —
   three mutations survived, including removing the `match_dot: true` that the file's own
   comment cites as its reason for existing. The probes guarded target resolution; the
   enumeration was unguarded.

So: **read the step's line, not just the exit code**, and derive the probe's input the way the
mechanism derives its own — same command, same source of truth.

## CI is unproven until a run exists

A committed workflow reads like a working one. It is not. Until a real run has gone green on a
real ref, the commit that adds a workflow says so in its message, and no record claims the
workflow passes.

The same rule covers the toolchain a workflow pins: `setup-beam` resolving a given OTP/Elixir
pair on a given runner image is a claim about someone else's infrastructure, and it is
unverified until observed.

**Observed, and accepted rather than pinned.** The workflow asks for `otp-version: 28` and
`elixir-version: 1.18`. What CI installs is:

    Installing Erlang/OTP OTP-28.5.0.6 - built on amd64/ubuntu-24.04
    Using Elixir 1.18.5 (built for Erlang/OTP 27)
    Erlang/OTP 28 [erts-16.4.0.6]
    Elixir 1.18.5 (compiled with Erlang/OTP 27)

**An Elixir 1.18.5 build compiled for OTP 27, running on OTP 28.** The gate passes on it.

This is **recorded, not pinned**, and the reason is that pinning is the change which looks
more rigorous and is worse: Elixir 1.18 publishes no `otp-28` build, so pinning
`1.18.5-otp-28` would fail to resolve, and moving to an Elixir line that has one is a
toolchain decision rather than a CI tidy-up. Revisit when the Elixir pin next moves.

The point of writing it down is that the next person to read the workflow sees `otp-version: 28`
and `elixir-version: 1.18` and would reasonably assume a matched pair. It is not one, it is
known not to be one, and nothing here depends on it being one.

## Every "verified" names its command and its exit code

Counts are quoted from command output, never typed fresh. A red is demonstrated before a fix,
and the output is recorded verbatim. Corrections are appended, never rewritten.

## A verbatim archive is written by a command that fetches it, or it does not exist

"Verbatim" is a claim about bytes, and a hand transcription cannot make it true. Either a
command reads the source and writes the file -- so the bytes are the source's bytes -- or the
file is not an archive and is not labelled one. Citing where the original lives is always
available and always honest; a copy that has drifted is worse than a citation, because it
looks like evidence.

**Derivation.** A sibling tree archived eight reviewer verdicts by hand under the label
"Archived verbatim". Diffed against the source afterwards, four were abridged, one was a
different round's verdict entire, and one contained a sentence the reviewer never wrote --
an attestation of independent verification lifted from another round with the identifiers
substituted. That last is **fabricated evidence**, and it is named as such rather than as a
transcription error: the others moved real text to the wrong place, while that one created a
verification claim nobody made, inside the file offered as proof of what was said. All four
unreliable files were deleted rather than repaired.

This is the rule above applied to a copied artefact rather than a measured one, and it
belongs to the same family as a mutation reported as applied but never applied: **an archive
reported as verbatim but never fetched is indistinguishable from evidence, which is what
makes it the worst member of that family.**

## The README states what the package does today, and every behavioural claim in it is pinned

Two halves, and the second is what makes the first survive.

**The README moves in the slice that changes the behaviour**, not after it. A slice that changes
what the package does and leaves the README describing the old behaviour has shipped a false
statement to the artifact a consumer reads first — `mix.exs` puts `README.md` in the Hex package
`files:` list and makes it the ex_doc landing page, so after `mix.exs` it is the most-read live
file in the tree.

**Every behavioural claim in it is pinned by a test that runs.** `test/beam_mcp/readme_claims_test.exs`
is where that is discharged: one file, so a reader auditing the rule reads one file rather than
grepping a suite, and each test **quotes the README sentence it pins** and asserts that sentence
is still present. A claim that moves without its test fails loudly; a test pinning a sentence
nobody makes any more fails too, because a test guarding a deleted claim reads as coverage while
guarding nothing.

**Derivation, and it is two failures rather than one.**

The first is the ordinary one. A slice fixed a version-blind clause and updated the inline
comment, and left the `@moduledoc` — the module's published documentation — still stating the
rule the change deleted. A reviewer made it a blocking finding. The same slice then replaced a
README paragraph that overstated a rule with another paragraph that overstated it, in the fix
for the first.

The second is the one that produced this rule. Releasing that work as `0.2.0` — a minor bump
chosen specifically so a consumer *could* pin away from a documented wire break — the README
still recommended `{:beam_mcp, "~> 0.1"}`. Measured with Elixir's own `Version` module rather
than recalled:

    ~> 0.1     0.1.0=true   0.2.0=true      <- spans the break
    ~> 0.2     0.1.0=false  0.2.0=true      <- does not

Nothing was broken: a new user copying the snippet installs the right version. The defect is the
other direction — a consumer who copied it at `0.1.0` is carried across the break by a routine
`mix deps.update`, with no change to their own requirement and no signal. **The release shipped
the version signal and the advice defeating it in the same commit.**

It survived a deliberate sweep for stale version strings because the stale string was `0.1`, not
the `0.1.2` that changed. That is the whole argument for pinning the *class* with tests rather
than grepping for the *string*: a grep finds what you already thought of.

## A report owed only at the end is a report a crash deletes

The record is written when each **round** closes, not when the run does. A session that is
terminated mid-work — a rate limit, a crash, a compaction — takes every unwritten conclusion with
it, and the work then has to be redone from the tree rather than read from the record.

This is not about diligence. It is about where the finding lives: in the run's memory, it is lost
by any of the ordinary ways a run ends; in the issue, it survives all of them.

## An anchor that cannot move under the mutation carries no information

A test that pins a fix must be able to **fail** when the fix is removed. Two shapes fail that and
look identical to a passing suite:

- **The contained anchor.** Asserting `old_count == 0` proves nothing when the replacement embeds
  the original — the old string is still there, inside the new one. Assert `new_count == 1`, and
  prove application **by effect**: the mutant must change an observable outcome, not a substring.
- **The compiler kill.** A mutant that leaves a function or attribute unused is rejected by
  `--warnings-as-errors` before the suite runs. The build failed; no test did anything. Complete
  the mutation — remove what it orphans — and re-run, or the table records a kill that never
  happened.

A survivor that is genuinely equivalent is recorded as a survivor, with the argument for why. The
alternative is writing a test that asserts an implementation detail so the table can read
all-killed, which is worse than the survivor: it looks like evidence and is not.

## Every place a mechanism reads the same kind of input is one mechanism

When a defect is "this read handles the input wrongly", the fix is not that read. Derive the set
of places that read that input — with a command, recorded, so the derivation is repeatable — and
change all of them, through one path if the comparison allows it. Then say in the record **how the
set was derived**, so the next reader can re-derive it rather than trust the list.

The test of the fix is that a new member of the set inherits the behaviour instead of needing a
new finding. Fixing three of four named header reads and leaving the fourth is how the same defect
was found twice in code written by the commit that fixed it the first time.
