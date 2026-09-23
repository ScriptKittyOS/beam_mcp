<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Governance

Who decides what, how a change lands, and what an outside measurement (the OpenSSF
Scorecard) reads of it. Written to state what is true of this repository today, including
the parts a larger project would have and this one does not.

## Who

**One maintainer.** The repository `ScriptKittyOS/beam_mcp` is owned by the ScriptKittyOS
organization; its one administrator is the maintainer, who is also the Hex package's owner
and the address `SECURITY.md` names. `CODEOWNERS` names that login for every path. There is
no steering group and no vote: a decision is the maintainer's, recorded in the tree (a
CHANGELOG entry, a page, a test) or it was not made. From 2026-09-23 pull requests are
reviewed by `znmead`, who knows the code, as well as by the maintainer. **For continuity**, two
people hold access: `znmead` and Mike Hostetler the Maintain role here, and Mike maintainer
ownership on hex.pm, so issues, merges and releases can go on without the maintainer; neither
decides anything while the maintainer can. The **bus factor is two**: the maintainer and
`znmead` both know the code; `docs/succession.md` says what that means, what the access covers,
and what a successor would need.

## How a change lands

Every change, the maintainer's included, goes the same way:

1. **A branch and a pull request.** `main` is protected by a ruleset: no direct push, no
   force-push, no deletion, linear history, and two required status checks: the DCO sign-off
   and the quality gate. A pull request is the only way onto `main`, and it is rebased, never
   merged, so the history is a line.
2. **The gate.** `tools/gate.sh` runs the same sixteen steps locally and in CI (format,
   compile with warnings as errors, Dialyzer, the instruments' parse, the suite, Credo, the
   properties, the optional-dependency probe, the dependency audit, the benchmarks, the docs,
   REUSE, the licence files, the publication census, the public-API baseline against
   `origin/main` and the commit-message terms) on three
   OTP/Elixir pairs (the floor, the pinned line, the newest). There is no baseline to hold: a
   non-zero count is a failure.
3. **Review by tier, then the merge word.** `CONVENTIONS.md` states the tier rule: a contract
   change (behaviour a consumer can hit) gets two independent review lanes and mutation
   testing against every pin; a measurement change (CI, gates, pins that make an existing
   claim true) gets one lane and one round; prose and records get the gate and a self-review.
   A lane's verdict is bound to the tree it read (`tools/signoff.sh`), and the merge happens
   on the maintainer's explicit word after the records say approve on the tree in front of
   them. The review lanes are not a second maintainer: they read, plant, measure and report;
   the maintainer decides.
4. **The record.** What a change claims, it shows: a red before a fix, counts quoted from
   command output, a CHANGELOG entry in the shape `docs/api-stability.md` requires when the
   public surface moves. A claim without a measurement behind it is filed as a gap, not
   written as a fact.

## What the Scorecard reads, and what this project keeps of it

The [OpenSSF Scorecard](https://scorecard.dev/viewer/?uri=github.com/ScriptKittyOS/beam_mcp)
runs on every push to `main` and once a week (`.github/workflows/scorecard.yml`) and publishes
its result. It is a measurement of the tree and the platform, and this page says which of its
checks this project keeps on purpose, which it cannot, and which it has decided against, so a
reader does not have to guess whether a low mark is neglect or a decision.

The figures are the Scorecard's own, read from `api.scorecard.dev` on 2026-09-19 (aggregate
**7**), and say what the check measured beside what the tree holds; a figure is quoted, not
promised, and moves when the Scorecard next runs.

| check | this repository | why | measured 2026-09-19 |
| --- | --- | --- | --- |
| Pinned-Dependencies | every workflow action pinned by commit SHA with its version beside it; Mix dependencies locked in `mix.lock` | a tag can be moved, a SHA cannot; a test holds the pins on every push | 10, "all dependencies are pinned" |
| Token-Permissions | every workflow declares top-level `permissions:` with no write; the two jobs that write (provenance's attestation, the Scorecard's SARIF upload) hold it at the job, and no other job does | least privilege, held by the same test: the top level, and which jobs may write | 10 |
| Branch-Protection | the ruleset above: no direct push, linear history, required checks | kept; **no required reviewer**; see Code-Review | 4, "not maximal": the missing tiers are the required reviewer and a second approver, which one maintainer cannot supply |
| Code-Review | pull requests, every one since the ruleset (2026-09-06; the eight bootstrap commits before it were pushed directly); the reviewer of record is the maintainer, after the lanes | one maintainer cannot approve their own pull request under GitHub's rules, and there is no second one; the Scorecard scores this low and that is the true state, not an omission | 0, "0/7 approved changesets" |
| Security-Policy | `SECURITY.md` | the intake, the rubric and the CVE path | 10 |
| License | `LICENSE`, `NOTICE`, `LICENSES/`, REUSE headers on every file, held by the gate | | 10 |
| Dependency-Update-Tool | Dependabot, weekly, Mix and GitHub Actions | | 10 |
| Vulnerabilities | `mix hex.audit` in the gate, OSV-fed, on every push | | 10 |
| CI-Tests | the gate on three OTP/Elixir pairs | | 10, "7 out of 7 merged PRs checked" |
| Maintained | commits and releases as the CHANGELOG shows | the check scores **0 for any repository younger than 90 days**, whatever its activity; this one was created 2026-09-06, so the figure is the rule's until 2026-12-05 and says nothing about the tree | 0, "created within the last 90 days" |
| Signed-Releases | releases are Hex releases: from `0.6.0` on, the tarball is built by CI on the tag and attested (`docs/provenance.md`; `0.5.0` and earlier carry none); there are no GitHub Releases with assets for this check to read | the attestation binds to the checksum hex.pm shows, which is where consumers fetch from; a GitHub Release would be a copy | −1, "no releases found": the check reads GitHub Releases only |
| Packaging | the package is published to hex.pm by the maintainer from the canonical tarball, on a signed tag; no GitHub Actions publishing workflow | the publish step holds a Hex API key, which stays on the maintainer's seat rather than in a workflow secret: a decision, recorded here; the provenance workflow attests the bytes but does not publish them | −1, "packaging workflow not detected": the check reads a publishing workflow only |
| SAST | Dialyzer and Credo in the gate; no CodeQL | the gate's analysers are what the language has; a CodeQL workflow is a separate decision and is not taken here | 0, the check recognises neither Dialyzer nor Credo |
| Fuzzing | eleven property-based tests in the gate; no OSS-Fuzz | property tests are the fuzzing the suite does; OSS-Fuzz integration is not taken | 10, "project is fuzzed": the check reads the property tests as fuzzing |
| CII-Best-Practices | **silver** since 2026-09-23 ([project 14774](https://www.bestpractices.dev/projects/14774)), passing the same day; continuity of access met by the two people `docs/succession.md` names; every answer cites this tree, and one that stops being true is changed there | the badge is a self-assessment a reader can check line by line; the bus factor is answered Met, two people knowing the code | 2, "badge detected: InProgress" (the run of 2026-09-23 17:26 UTC, before passing was recorded; the check gives passing 5, silver 7, gold 10) |
| Dangerous-Workflow | the pull-request body is read through an environment variable, never interpolated into a script | | 10 |
| Binary-Artifacts | none in the tree | | 10 |
| Contributors | one organization owns the repository; the NOTICE names the owner and the builder | the check counts the companies commit authors declare, and read two | 6, "2 contributing companies or organizations" |

## What is deliberately not done

No second maintainer is invented to satisfy a check. No GitHub Release is published beside
the Hex release to satisfy a check. No analyser is added for its name. Where a check reads
low for a reason this page states, the reason stands until the fact changes: a second
maintainer is `docs/succession.md`'s subject, and the off-account archive of the private
records waits on a decision recorded there.
