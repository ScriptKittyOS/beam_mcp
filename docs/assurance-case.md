<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Assurance case

Why this package's security requirements are met: the claim, the threat model it is made
against, where trust changes, the design principles applied, and the common implementation
weaknesses countered. Each argument points at the evidence (a test, a census, a page) rather
than restating it, so the evidence can be checked and this page cannot drift far from it.

## The claim

**A client on the wire, sending any bytes, cannot make this package do more than the host
declared, cannot make it consume unbounded resources, and cannot read the host's internals
through it.** Specifically: a request is read under a bound, decoded under a bound, answered
in the protocol revision it declared, validated against the schema the host advertised before
anything the host wrote runs, and refused by name when any of that fails. The package holds no
key, no session and no authority, so there is none to take from it.

What the claim does **not** cover, by decision and stated in the threat model: code already
running in the same BEAM node, what a host's tool does with a valid call, and what a tool's
result does to a language model.

## The threat model

`docs/threat-model.md` is the threat model. It names the parties and what each is trusted for,
then takes the wire vector by vector (oversized bodies, deep nesting, repeated keys, malformed
input, header and body disagreement, request smuggling, DNS rebinding, slow clients, floods,
unsafe deserialization, arguments the schema does not admit, sessions, error leakage, the
supply chain) and marks each one REFUSED, BOUNDED or DELEGATED, with the test that enforces
it named by path and by title. A census (`test/beam_mcp/threat_model_test.exs`) fails if the
page cites a test that does not exist.

## Trust boundaries

The trust table at the top of `docs/threat-model.md` is the authoritative statement. In short,
trust changes at three places:

1. **The wire, into the transport.** Client bytes are untrusted. Everything past
   `BeamMCP.Transport.Stdio` or `BeamMCP.Transport.HTTP` has been read under the 1 MiB cap and,
   over HTTP, a whole-body deadline and an `Origin` check.
2. **The decoder, into the core.** `BeamMCP.JSON` is the one reader on both transports; past
   it, a message is plain data with bounded nesting and no repeated key.
3. **The core, into the host.** The catalog and the dispatch function are the host's and are
   trusted; a call reaches dispatch only after `BeamMCP.Schema` has checked it against the
   schema that same catalog advertised, at every depth. A fault inside the host is answered as
   a fault naming the broken contract, and its details stay on the host's side: the host's
   module and term never reach the client, and the transport's report (on standard error over
   stdio) carries a stacktrace of arities, never arguments.

A fourth boundary is named and not crossed: the BEAM node. The package does not claim to
protect against code running in the same node, because the runtime offers no isolation there.

`docs/architecture.md` shows where each of these sits in the request path.

## Secure design principles applied

The principles are Saltzer and Schroeder's, as the criterion suggests.

| principle | how it is applied here | evidence |
|---|---|---|
| Economy of mechanism | One JSON reader for both transports and the pagination cursor; one declaration serves both advertising and accepting; one cursor for every list; one digest call site. The core is a function with no process and no state. | `BeamMCP.JSON`; `BeamMCP.Catalog`; `BeamMCP.Cursor`; `lib/beam_mcp/connectome/canonical.ex` (the one `:crypto.hash/2`) |
| Fail-safe defaults | `allowed_origins:` has no default and `init/1` raises without it. An absent catalog key is a malformed catalog, refused at startup. An undeclared tool is refused. The tracer and collector are off unless started, and bounded when started: the tracer's limits have finite defaults and refuse an unbounded value. The only built-in signer signs nothing. | `test/beam_mcp/transport/http_test.exs` "init/1 raises without :allowed_origins"; `BeamMCP.Server.new/1`; `BeamMCP.Signer.None` |
| Complete mediation | Every `tools/call` is validated against the advertised schema, at every depth, and a keyword the server would not enforce is refused at startup rather than advertised; every HTTP request's `Mcp-*` headers are matched to its body; no session exists, so no request inherits a check made for another. | `test/beam_mcp/tool_spec_schema_test.exs`; `test/beam_mcp/boundary/no_session_test.exs` |
| Open design | Source is Apache-2.0; the canonical byte format is specified so a verifier needs nothing from this package; nothing depends on an attacker not knowing how it works. | `docs/connectome-canonical.md` |
| Separation of privilege | Deciding (a verdict, a key, an approval) is kept out of the package and with the host or a separate package; the signer that holds a key is a separate package the host attaches. | `docs/will-not-implement.md` entries 1 to 4; `BeamMCP.Signer` |
| Least privilege | The package holds no key, opens no outbound connection, runs no command and evaluates no code. The modules and functions it may call are pinned by a census over the compiled code. CI workflows hold write permission only in the two jobs that need it. | `test/beam_mcp/boundary/package_reach_test.exs`; `test/beam_mcp/boundary/no_key_holding_test.exs`; `docs/governance.md` (Token-Permissions) |
| Least common mechanism | No state is shared between requests or between clients. The observed-graph collector is a process the host starts in its own supervision tree, not a global. | `BeamMCP.Server` moduledoc; `BeamMCP.Connectome.Observed` |
| Psychological acceptability | A refusal names its cause (`-32600` "Request body nests deeper than 64 levels") and carries structured fields, so a host developer can act on it without reading package source. | `test/beam_mcp/error_payload_test.exs` |

Beyond the eight: **input is validated against an allowlist** (the schema the host declared,
with `additionalProperties` honoured at every depth) rather than screened for known-bad values, and
**resources are bounded** at every place a client controls a size or a duration.

## Common implementation weaknesses countered

Mapped to CWE entries (most from the CWE Top 25) that apply to a network-facing protocol
library. Entries that cannot arise here are listed at the end with the reason.

| weakness | how it is countered | evidence |
|---|---|---|
| CWE-20 Improper input validation | Arguments checked against the advertised JSON Schema before dispatch; headers held to the body; non-object JSON refused by type. | `test/beam_mcp/tool_spec_schema_test.exs`; `docs/threat-model.md` rows "Tool arguments the schema does not admit" and "Header injection" |
| CWE-400 / CWE-770 Uncontrolled resource consumption | 1 MiB body and line cap; nesting refused past 64 levels before decoding; whole-body read deadline and connection deadline; chunked bodies refused; the tracer bounded by default. | `docs/threat-model.md` rows "Oversized body", "Deeply nested JSON", "Slow clients", "A body that does not declare its length" |
| Atom-table exhaustion (a CWE-400 case specific to the BEAM) | No atom is created from a client's key; the one `String.to_atom/1` runs over keys the host declared. Credo's `UnsafeToAtom` check runs on `lib/` in the gate. | `test/beam_mcp/argument_interning_test.exs`; `.credo.exs` |
| CWE-502 Deserialization of untrusted data | Input is decoded by `Jason` to plain data only; no `binary_to_term`, no evaluator, no module or function named from input. | `test/beam_mcp/boundary/no_dynamic_evaluation_test.exs` |
| CWE-94 / CWE-78 Code and command injection | No code evaluation and no OS command under `lib/`; the functions the package may call on modules that could reach code or the OS are pinned. | `test/beam_mcp/boundary/no_dynamic_evaluation_test.exs`; `test/beam_mcp/boundary/package_reach_test.exs` |
| CWE-209 / CWE-200 Information exposure through errors | Errors carry structured fields, never an inspected term; a host fault is `-32603` with no stacktrace; stacktraces that leave the package carry arities, not arguments. | `test/beam_mcp/error_payload_test.exs`; `BeamMCP.Stacktrace` |
| CWE-444 HTTP request smuggling | Framing is the HTTP server's; a refusal issued before the body is read closes the connection, so an unread body is never taken as the next request. | `docs/threat-model.md` row "Request smuggling at the HTTP layer" |
| CWE-350 / CWE-346 DNS rebinding, origin validation | `Origin` checked against a required allowlist before the body is read. | `docs/threat-model.md` row "DNS rebinding through Origin" |
| CWE-384 / CWE-613 Session fixation and expiry | No session identifier is issued, honoured or read. | `test/beam_mcp/boundary/no_session_test.exs` |
| CWE-798 / CWE-321 Hard-coded credentials and keys | The package holds no key and names no key material under `lib/`; the history is scanned for secrets. | `test/beam_mcp/boundary/no_key_holding_test.exs` |
| CWE-327 / CWE-328 Broken or risky cryptography | The only cryptographic operation is a SHA-2 digest (SHA-256 by default, SHA-384 or SHA-512 by option), named in the bytes so it can be changed. | `docs/crypto-posture.md` |
| CWE-1104 / CWE-1395 Vulnerable third-party components | Four dependencies, locked in `mix.lock`; `mix hex.audit` in the gate on every push; Dependabot weekly. | `tools/audit.sh`; `.github/dependabot.yml` |

**Not applicable here**, and why: CWE-79 (cross-site scripting) and CWE-89 (SQL injection),
because the package renders no HTML and runs no query; CWE-22 (path traversal), because it
reads no file named by input (a resource is read by the host's callback); CWE-787 and CWE-125
(out-of-bounds write and read), because it is written in Elixir with no native code;
CWE-287 and CWE-862 (authentication and authorization), because both are the host's, through
its `authorize/1` and `authorize_body/2` hooks, and the package says so rather than offering a
partial scheme.

## How the case is kept true

- The gate runs on every push on three OTP/Elixir pairs; the censuses above fail when the code
  they describe changes.
- The threat model's citations and the will-not-implement page's entries are each held to the
  test suite by a census of their own.
- A new wire-facing feature changes this page and the threat model in the same pull request.

## Related

`docs/threat-model.md`, `docs/architecture.md`, `docs/crypto-posture.md`,
`docs/will-not-implement.md`, `SECURITY.md`.
