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

**It makes no signature.** No signing or MAC primitive is called under `lib/`, and no function
named `sign` is defined there (entry 3; `test/beam_mcp/boundary/no_signature_test.exs` "no
line under lib/ calls a signing or MAC primitive or defines a sign function"). What a
consumer signs is the hash, or the bytes, with a key the consumer holds; the canonical bytes
exist so that it can do so without importing this package. The seam is one function with one
argument, `sign(canonical_bytes, opts)`, in a separate package — decided, not built; a
post-quantum signature (ML-DSA) would live there and change nothing here, since the envelope
already names its digest.

**It performs no cryptography on a request.** The HTTP transport's `:authorize_body` hook
hands the host the body exactly as received so the host can verify a signature over it; the
package does not (`README.md`, "This Plug performs no cryptography."). Origin, method,
length, size and time bounds are not cryptography and are the threat model's
([`docs/threat-model.md`](threat-model.md)).

**It does not enable FIPS mode, and cannot.** What a FIPS-mode host needs from this package,
and what the package needs from the host, is [`docs/fips.md`](fips.md).
