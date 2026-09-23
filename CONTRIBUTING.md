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
script. To have git run it for you, `./tools/install-hooks.sh` once per clone points
`core.hooksPath` at the tracked `tools/hooks/`: `pre-commit` runs the gate, `commit-msg` reads
the message through `tools/text_terms.sh` (the terms in rule 2, and no board ids). It is
opt-in; `--uninstall` undoes it; `git commit --no-verify` is git's own bypass and CI still runs
the gate.

**4. Rebase, never merge.** Keep history linear. Rebase onto `main` and force-push your branch
rather than merging `main` into it.

## Getting set up

```sh
git clone https://github.com/ScriptKittyOS/beam_mcp && cd beam_mcp
asdf install            # the Erlang/OTP and Elixir versions .tool-versions pins (any manager that reads it works)
mix deps.get
mix test                # the suite
./tools/gate.sh         # everything CI runs
```

Erlang/OTP 27 or newer and Elixir 1.17 or newer are supported; `.tool-versions` names the pair
the maintainer develops on. The HTTP transport's optional dependencies are fetched by
`mix deps.get` in development and test.

## Coding style

The style guide is the Elixir community's: the output of `mix format` (the project's
`.formatter.exs`) and the checks of [Credo](https://hexdocs.pm/credo/) in `--strict` mode,
which implement the [Elixir Style Guide](https://github.com/christopheradams/elixir_style_guide)
and add readability, consistency, design and warning checks, including the security-relevant
warnings `.credo.exs` enables. Contributions are expected to comply; the gate enforces both,
so a change that does not is red. Beyond them, `CONVENTIONS.md` records this project's own
rules for tests, measurements and records.

## Tests for new functionality

**Every change that adds or changes behaviour adds tests for it to the automated suite, in
the same pull request.** A new function, option, protocol method or refusal is not accepted
without a test that exercises it; a bug fix carries a regression test that was seen failing
before the fix (below). A change to the wire or to the host contract is also measured by
mutation, as `CONVENTIONS.md`'s tier rule says. A pull request without its tests is sent
back, whoever wrote it.

## Code review

**How it is done.** Every change reaches `main` through a pull request, the maintainer's
included, and is merged by rebase only after CI is green on all three OTP/Elixir pairs. The
reviewer reads the diff, the commit messages and the CI results, and runs the change locally
when it touches the wire or the host contract. `CONVENTIONS.md`'s tier rule sets the depth: a
contract change (behaviour a consumer can hit) gets two independent review passes and mutation
testing against every pin it adds; a measurement change (CI, gates, pins) gets one pass; prose
gets the gate and a self-review. Automated review passes and the censuses assist; they do not
replace the reviewer's judgement.

**What must be checked.**
- The change does what its message says, and nothing else (one change per commit).
- New or changed behaviour has tests; a fix has a test that was seen failing first.
- Wire-facing input stays bounded and validated: a new path through `BeamMCP.JSON`, the
  transports or `BeamMCP.Server` keeps the size, nesting, header and schema checks, and adds no
  atom, evaluation, file or network access driven by a client
  (`docs/threat-model.md`, `docs/assurance-case.md`).
- Nothing crosses the boundary `docs/will-not-implement.md` draws; the censuses under
  `test/beam_mcp/boundary/` still pass for the right reason.
- The public surface: if `docs/public-api.txt` moves, the CHANGELOG names the exact entry and
  the break rules in `docs/api-stability.md` are followed.
- Pages that describe the changed behaviour (README, threat model, assurance case) change in
  the same pull request.
- Sign-off on every commit, no attribution trailers, no secret in the diff.

**What is acceptable.** All of the above hold, CI is green, and the reviewer can say why the
change is correct. Anything short of that is sent back with the reason. **Who reviews:** the
maintainer reviews every pull request; the continuity holders named in `docs/succession.md`
may review as well. A review by a person other than the author on at least half of all changes
is the project's aim; the pull requests show who reviewed each one.

## What a change is expected to carry

- **A red before a fix.** Show the failure first, in the commit message, with its output. A
  test that has never been seen failing is not evidence that it works. Where a red is not
  available — the code already exists and passes — demonstrate coverage by mutation instead:
  break the property in a throwaway copy and show the test catches it.
- **Counts quoted from command output, never typed.** Test counts, exit codes, file counts.
- **SPDX headers** on every `.ex`, `.exs`, `.sh` and `.yml`. The gate checks it, and CI runs
  the REUSE Specification's own lint over the whole tree (`pipx run reuse==6.2.0 lint` locally, the version CI pins;
  `REUSE.toml` covers the slice archives).
- **Scope discipline.** One commit does one thing and says so. If a fix uncovers a second
  defect, file it rather than folding it in.

`CONVENTIONS.md` records why these exist, with the specific failures that produced them.

## Conduct

Participation is under the [Code of Conduct](CODE_OF_CONDUCT.md) (the Contributor Covenant,
version 2.1).

## Reporting a vulnerability

Not here. See `SECURITY.md`.
