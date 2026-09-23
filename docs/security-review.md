<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Security review

How a security review of this package is done, and the record of each one. A review is a
person reading the code against the package's security claims; the tools (the censuses, Credo,
Dialyzer, the property tests, automated review passes) support it and do not replace it, because
the design questions below are ones a tool cannot answer. One is done at least every five
years, and before `1.0.0`.

## What it is measured against

- **The security requirements:** what `SECURITY.md` says is in scope, and the claim in
  `docs/assurance-case.md`.
- **The security boundary:** the trust table and the wire vectors in `docs/threat-model.md`,
  and what `docs/will-not-implement.md` says the package never does.

## The checklist

Each item is answered with what was read (file and function), what was tried, and what was
found. "Held" needs a reason, not a tick.

1. **Bounds on the wire.** Read `BeamMCP.JSON` and both transports. Is every read under the
   1 MiB cap, every decode under the nesting bound, every repeated key refused? Try a body one
   byte over the cap, one level too deep, and a repeated key, on both transports.
2. **HTTP request checks.** `Origin` required and matched before the body is read; every
   `Mcp-*` header held to the body; chunked bodies refused; the read and connection deadlines
   in force. Try a disagreeing header and a disallowed origin.
3. **Validation before dispatch.** In `BeamMCP.Server`, can any path reach the host's dispatch,
   `read_resource/1` or `get_prompt/2` without the declared schema having been checked? Try an
   undeclared tool, a missing required argument and a forbidden extra one.
4. **What a client can make the node do.** Search `lib/` for atom creation, evaluation, file,
   OS, network or distribution calls reachable from input. Compare with the census lists in
   `test/beam_mcp/boundary/package_reach_test.exs`: does each listed call still earn its place?
5. **What leaks back.** Errors, telemetry metadata and log lines: do any carry an inspected
   term, a stacktrace with arguments, or the client's bytes? Force a host fault in dispatch and
   a hook, and read what the client and the log receive.
6. **Cryptography and keys.** One `:crypto.hash/2` site, SHA-2 only, no key named under `lib/`
   (`docs/crypto-posture.md`); the signer seam passes bytes out and a signature in, nothing else.
7. **The opt-in parts.** The tracer and the observed collector: limits required and enforced,
   nothing left behind after `stop/0`, no payload byte in an edge.
8. **Supply chain and release.** `mix.lock` against `mix hex.audit` and the advisories for each
   dependency; workflow permissions and pinned actions; the release tarball rebuilt with
   `tools/release_tarball.sh` and compared with hex.pm's checksum and the attestation
   (`docs/provenance.md`).
9. **The pages.** Does each row of the threat model and each argument in the assurance case
   still describe the code? A row that no longer holds is a finding.

## After a review

Findings are handled as `SECURITY.md` says (a private advisory where one is warranted), each
with an issue or a pull request. The review is recorded below in the pull request that adds the
row: the date, who did it, the commit reviewed, the scope, and what was found.

## Record

| date | reviewer | commit | scope | findings |
|---|---|---|---|---|

No review has been recorded yet. The threat model (`docs/threat-model.md`) and the assurance
case were written with automated review passes against the code, which is groundwork for the
first review and not a review under this page's definition.
