<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# FIPS mode

What a host running under FIPS 140 needs from this package, and what this package needs
from the host. The package enables nothing: FIPS mode belongs to the runtime the host builds
and starts, and every sentence here about the runtime is Erlang/OTP's documentation for
`crypto`, cited so a host verifies it there rather than here.

## What the package needs from a FIPS-mode host

Only that `:crypto.hash/2` answer for `:sha256`, `:sha384` and `:sha512`. Those are the SHA-2
digests of FIPS 180-4, approved under FIPS 140-3, and they are the only three names the
canonical envelope may carry ([`docs/crypto-posture.md`](crypto-posture.md)). Nothing this
package calls is disallowed in FIPS mode: it uses no MD5, no SHA-1, no cipher, no MAC, no
key derivation and no random source — `:crypto.hash/2` at one site is its whole use of the
library (`test/beam_mcp/boundary/no_key_holding_test.exs`, both tests). A host that has
enabled FIPS mode therefore runs this package unchanged, and a graph hashed under FIPS mode
has the same bytes and the same hash as one hashed outside it: the digest is the digest.

## What a FIPS-mode host needs, and this package does not provide

FIPS mode is a property of the `crypto` application and the OpenSSL it is linked against,
and it is the host's to establish, in this order:

1. **An Erlang/OTP `crypto` built with FIPS support**, linked against an OpenSSL 3 whose
   **FIPS provider is installed and validated** on that machine. `:crypto.info/0` reports
   `fips_provider_available: true` when it is; `:crypto.info_fips/0` answers
   `:not_supported` when the build or the library cannot do it at all (measured on the
   development runtime that wrote this page — OpenSSL 3.0.13, no FIPS provider — where it
   answers exactly that and `:crypto.enable_fips_mode(true)` answers `false`).
2. **The `crypto` application started** — `application:start(crypto)`, which a release does
   for every application its `.app` files require: this package's `.app` lists `crypto` as
   a required application, so a release that includes `beam_mcp` starts it (it did not
   until 0.6.0 — an HTTP host had `crypto` only through `plug` and `bandit`, both optional,
   and a stdio-only release would have had no `:crypto.hash/2` at all; writing this page
   found it, and `test/beam_mcp/connectome/canonical_test.exs` "the .app the build writes
   depends on crypto, so a release without plug and bandit still hashes" holds it) — before
   FIPS mode is enabled, because the mode is set on the running application.
3. **FIPS mode enabled by the host**, either with `:crypto.enable_fips_mode(true)` at start
   (it answers `true` when the provider took, `false` when it did not, and a host that
   requires FIPS mode treats `false` as a fault) or with the `crypto` application
   environment `fips_mode: true`, which enables it at application start.
   `:crypto.info_fips/0` then answers `:enabled`; a host that requires FIPS mode checks it
   at start and refuses to serve otherwise.

This package calls none of `:crypto.enable_fips_mode/1`, `:crypto.info_fips/0` or
`:crypto.info/0`: they are barred from `lib/` by the same census that bars every `:crypto.`
function but `hash/2`, so the package cannot enable FIPS mode by accident or on purpose,
and cannot report on it — the host's start-up is where that check lives. Nothing here is a
claim that this package, or a host running it, is FIPS-validated: validation is a property
of a cryptographic module (the OpenSSL FIPS provider) and of the process that certified it,
and this package holds no such module.

## What FIPS mode changes for a consumer

Nothing about the bytes or the hash. A verifier in FIPS mode and one outside it compute the
same digest over the same bytes; the algorithm the envelope names is one the FIPS provider
serves. A consumer whose policy accepts only SHA-384 or SHA-512 asks the host for that
`algorithm:` and refuses envelopes naming another — the consumer's policy, stated in the
consumer ([`docs/connectome-canonical.md`](connectome-canonical.md), rule 9).
