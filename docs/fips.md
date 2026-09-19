<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# FIPS mode

What a host running under FIPS 140 needs from this package, and what this package needs
from the host. The package enables nothing: FIPS mode belongs to the runtime the host builds
and starts. What this page says about the runtime is Erlang/OTP's documentation for
`crypto`, restated and quoted where the words matter, so a host verifies it there rather
than here; the two sentences below that are this page's own inference from OTP's source are
marked as such.

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
   `:not_enabled` — when FIPS mode was not requested; when it was, see the next step, since
   OTP does not load at all. Measured on the development runtime that wrote this page (OTP 28.1.1,
   OpenSSL 3.0.13, no FIPS provider): `:not_supported`, `fips_provider_available: false`,
   and `:crypto.enable_fips_mode(true)` answers `false`.
2. **The `crypto` configuration parameter `fips_mode: true`, in the application environment
   before the `crypto` module is first loaded** — in `sys.config` or the release's
   configuration, not set at runtime after the fact. In OTP's words, "this setting will
   take effect when the nif module is loaded", and: **"if FIPS mode is requested but not
   available at run time the nif module and thus the crypto module will fail to load. This
   mechanism prevents the accidental use of non-validated algorithms."** So a host that sets
   the parameter on a runtime without a validated provider does not get `:not_enabled` — it
   gets no `crypto` at all: `application:start(crypto)` fails, and a release whose `.app`
   requires `crypto` (this package's does) does not boot. That is the failure a FIPS host
   wants, and it comes before any check this page could suggest. (This page's own inference
   from OTP's `on_load`, not OTP's words: the parameter is read once, when the module loads,
   so a value set after that changes nothing until the module is loaded again.) This is
   why OTP says `crypto:start/0` "does not work if FIPS mode is to be enabled" and to use
   `application:start(crypto)` instead: the application must be loaded, with its
   environment, before the module is. A release does this for every application its `.app`
   files require, and this package's `.app` lists `crypto` as a required application, so a
   release that includes `beam_mcp` loads and starts it (it did not until 0.6.0, the release
   this page arrives in — an HTTP host had `crypto` only through `plug` and
   `bandit`, both optional, and a stdio-only release would have had no `:crypto.hash/2` at
   all; writing this page found it, and `test/beam_mcp/connectome/canonical_test.exs`
   "the .app the build writes depends on crypto, so a release without plug and bandit still
   hashes" holds it).
3. **A check at start, for the belt beside OTP's braces.** `:crypto.info_fips/0` answers
   `:enabled` once the parameter took; a host that requires FIPS mode may check it at start
   and refuse to serve otherwise, though under the parameter OTP's own refusal (the module
   not loading) comes first. The
   older way, `:crypto.enable_fips_mode(true)` at runtime (`true` when it took, `false`
   when it did not), **is deprecated in OTP 28** — "use config parameter fips_mode", in
   the deprecation's own words — and is named here only so a host reading older guidance
   knows what replaced it.

This package calls none of `:crypto.enable_fips_mode/1`, `:crypto.info_fips/0` or
`:crypto.info/0` — the three are barred from `lib/` by the same census that bars every
`:crypto.` function but `hash/2` — and it sets no application environment: the
package-reach census (`test/beam_mcp/boundary/package_reach_test.exs`) pins the functions
called on `Application` to `load/1` and `spec/2`, reads only, so the package cannot enable
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
