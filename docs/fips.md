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
and it is the host's to establish. What follows is OTP 28's `crypto` documentation (the
`-doc` strings of `crypto.erl` in `crypto-5.7`, and its application configuration
parameters), restated; where this page and OTP's differ, OTP's is right.

1. **An Erlang/OTP `crypto` built with FIPS support** (the configure option
   `--enable-fips`), linked against an OpenSSL 3 whose **FIPS provider is installed and
   validated** on that machine. `:crypto.info/0` reports `fips_provider_available: true`
   when the provider is there. `:crypto.info_fips/0` answers, in OTP's words, `:enabled`
   when running in FIPS mode or `:not_enabled` if `crypto` was built with FIPS support, and
   "for other builds this value is always `:not_supported`" — so `:not_supported` names the
   build, not the provider: a FIPS-built `crypto` over a library with no provider answers
   `:not_enabled`. Measured on the development runtime that wrote this page (OTP 28.1.1,
   OpenSSL 3.0.13, no FIPS provider): `:not_supported`, `fips_provider_available: false`,
   and `:crypto.enable_fips_mode(true)` answers `false`.
2. **The `crypto` configuration parameter `fips_mode: true`, in the application environment
   before the `crypto` module is first loaded** — in `sys.config` or the release's
   configuration, not set at runtime after the fact. OTP reads the parameter when the
   `crypto` NIF loads (the module's `on_load`), and loads the library in FIPS mode or not by
   what it finds then; a parameter set after the module is loaded changes nothing. This is
   why OTP says `crypto:start/0` "does not work if FIPS mode is to be enabled" and to use
   `application:start(crypto)` instead: the application must be loaded, with its
   environment, before the module is. A release does this for every application its `.app`
   files require, and this package's `.app` lists `crypto` as a required application, so a
   release that includes `beam_mcp` loads and starts it (it did not until the release after
   0.5.0, the one this page arrives in — an HTTP host had `crypto` only through `plug` and
   `bandit`, both optional, and a stdio-only release would have had no `:crypto.hash/2` at
   all; writing this page found it, and `test/beam_mcp/connectome/canonical_test.exs`
   "the .app the build writes depends on crypto, so a release without plug and bandit still
   hashes" holds it).
3. **A check at start.** `:crypto.info_fips/0` answers `:enabled` once the parameter took;
   a host that requires FIPS mode checks it at start and refuses to serve otherwise. The
   older way, `:crypto.enable_fips_mode(true)` at runtime (`true` when it took, `false`
   when it did not), **is deprecated in OTP 28** — "use config parameter fips_mode", in
   the deprecation's own words — and is named here only so a host reading older guidance
   knows what replaced it.

This package calls none of `:crypto.enable_fips_mode/1`, `:crypto.info_fips/0` or
`:crypto.info/0`, and sets no application environment: they are barred from `lib/` by the
same census that bars every `:crypto.` function but `hash/2`, so the package cannot enable
FIPS mode by accident or on purpose, and cannot report on it — the host's configuration and
start-up are where that lives. Nothing here is a claim that this package, or a host running
it, is FIPS-validated: validation is a property of a cryptographic module (the OpenSSL FIPS
provider) and of the process that certified it, and this package holds no such module.

## What FIPS mode changes for a consumer

Nothing about the bytes or the hash. A verifier in FIPS mode and one outside it compute the
same digest over the same bytes; the algorithm the envelope names is one the FIPS provider
serves. A consumer whose policy accepts only SHA-384 or SHA-512 asks the host for that
`algorithm:` and refuses envelopes naming another — the consumer's policy, stated in the
consumer ([`docs/connectome-canonical.md`](connectome-canonical.md), rule 9).
