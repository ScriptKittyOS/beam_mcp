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
