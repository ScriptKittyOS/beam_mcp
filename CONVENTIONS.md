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

## Every "verified" names its command and its exit code

Counts are quoted from command output, never typed fresh. A red is demonstrated before a fix,
and the output is recorded verbatim. Corrections are appended, never rewritten.
