<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Contributing

## Four rules, all enforced

**1. Sign off every commit.** `git commit -s` adds the `Signed-off-by` line, which certifies
the [Developer Certificate of Origin](https://developercertificate.org/): you wrote the patch,
or have the right to submit it under this project's licence. **CI checks every commit in the
range and fails the whole push if one is missing.** A missing sign-off cannot be waived — the
history has to be rewritten to add it, which is easier before review than after.

**2. No tool-attribution trailers.** No `Co-Authored-By` naming a tool, no session links, no
generator banners. A commit message says what changed and why it is believed correct. Use of a
tool is not a fact about the change.

**3. The gate must be green.** `./tools/gate.sh` runs format, compile with
`--warnings-as-errors`, tests, `credo --strict`, an SPDX header check, and a licence-file
check. **There is no baseline and none will be added:** this tree started clean, so a non-zero
count is a failure rather than a number to hold. Run it before you push; CI runs the same
script.

**4. Rebase, never merge.** Keep history linear. Rebase onto `main` and force-push your branch
rather than merging `main` into it.

## What a change is expected to carry

- **A red before a fix.** Show the failure first, in the commit message, with its output. A
  test that has never been seen failing is not evidence that it works. Where a red is not
  available — the code already exists and passes — demonstrate coverage by mutation instead:
  break the property in a throwaway copy and show the test catches it.
- **Counts quoted from command output, never typed.** Test counts, exit codes, file counts.
- **SPDX headers** on every `.ex`, `.exs`, `.sh` and `.yml`. The gate checks it.
- **Scope discipline.** One commit does one thing and says so. If a fix uncovers a second
  defect, file it rather than folding it in.

`CONVENTIONS.md` records why these exist, with the specific failures that produced them.

## Reporting a vulnerability

Not here. See `SECURITY.md`.
