<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Cryptographic posture

What this package does with cryptography, in full, and what it leaves to the host and to a
consumer. Every sentence here names the test that holds it, in the way
[`docs/will-not-implement.md`](will-not-implement.md) does; where a sentence and a test
disagree, the test is the record.

## What the package does

**One primitive, one site.** The package computes digests and nothing else: `:crypto.hash/2`
is the only cryptographic function called under `lib/`, and it is called at one site, in
`BeamMCP.Connectome.Canonical`, over canonical bytes, with the algorithm a variable bound from
the caller's option and never a literal. Every other `:crypto.` function, every
`:public_key.` function, and every name that reads as key material is refused by census
(`test/beam_mcp/boundary/no_key_holding_test.exs` "no line under lib/ names key material or
calls a crypto function other than :crypto.hash/2" and ":crypto.hash/2 is called at one site,
over canonical bytes, with the algorithm a variable").

**Three digests, named in the bytes.** A canonical envelope — the graph's and the diff
record's — carries `"algorithm"` as a member: `"sha256"`, `"sha384"` or `"sha512"`, the SHA-2
family of FIPS 180-4, and its hash is that digest over exactly its bytes, so a verifier reads
the algorithm from what it holds rather than from a page or a release note
([`docs/connectome-canonical.md`](connectome-canonical.md), rules 1 and 9). SHA-256 is the
default the package writes when a caller names none, and stays the default indefinitely; the
other two are a caller's option (`algorithm:` on the canonical, diff and wire-surface
functions), never a compile-time constant, so a host moves to SHA-384 by a configuration
change and not a format break. A fourth name is refused at the option before a byte is
written; a verifier meeting one refuses the record. Bytes written before the member existed
(`schema_version` 1 and 2) are SHA-256 by the page's rule for those versions and stay
verifiable forever (`test/beam_mcp/connectome/canonical_test.exs` "an envelope tagged sha384
round-trips: the bytes name it and the hash is SHA-384 over them", "sha512 is the third
choice, and the three are the whole list", "an algorithm outside the list is refused at the
option by name, before any byte is written", "bytes at schema_version 2 stay verifiable the
way the migration note says: the version first, then SHA-256"; `test/beam_mcp/connectome/diff_test.exs`
"the record names its algorithm in the bytes, sha256 by default and sha384/sha512 by option,
and the hash follows"; `test/beam_mcp/connectome_vocabulary_test.exs` "every ratified term is
defined in the document", which holds the three names to `docs/connectome.md`).

**Why the algorithm is under the hash.** The member is part of the bytes, so two envelopes of
one graph naming different digests are different bytes with different hashes; neither can be
passed off as the other, and an attacker who can rewrite the member can rewrite the graph
anyway — the hash is over all of it. What the bytes cannot do is decide which of the three a
verifier accepts: that is the verifier's policy, stated in the verifier, and this package
neither asks nor answers it.

## What the package does not do

**It holds no key.** No line under `lib/` generates, loads, decodes or stores key material;
`plug_crypto`, which `plug` brings into the lock file, is barred by name
([`docs/will-not-implement.md`](will-not-implement.md), entry 2, and the census above).

**It makes no signature of its own.** No signing or MAC primitive is called under `lib/`
(entry 3; `test/beam_mcp/boundary/no_signature_test.exs` "no line under lib/ calls a signing or
MAC primitive"). What is signed is the canonical bytes, with a key the consumer holds, through
one seam: `BeamMCP.Signer`, a behaviour with exactly one callback, `sign(canonical_bytes,
opts)` — two arguments with those names, `{:ok, signature}` or `{:error, reason}`, pinned by
census so that any widening is a visible act — and `BeamMCP.Connectome.Canonical.signature/3`,
the one site that calls it, over the bytes `encode/2` produces, returning the signature beside
them and moving no byte. The one implementation here, `BeamMCP.Signer.None`, signs nothing;
the reference implementation that does, Ed25519 through OTP's `:crypto` with a key the host
hands in, is the separate package `beam_mcp_signer`, never a dependency of this one. A
post-quantum signature (ML-DSA) would be another module behind the same callback and change
nothing here, since the envelope already names its digest.

**It performs no cryptography on a request.** The HTTP transport's `:authorize_body` hook
hands the host the body exactly as received so the host can verify a signature over it; the
package does not (`README.md`, "This Plug performs no cryptography."). Origin, method,
length, size and time bounds are not cryptography and are the threat model's
([`docs/threat-model.md`](threat-model.md)).

**It does not enable FIPS mode, and cannot.** What a FIPS-mode host needs from this package,
and what the package needs from the host, is [`docs/fips.md`](fips.md).
