<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# The connectome — canonical bytes

This page is the contract for the bytes a connectome is hashed and signed over. It is complete
enough that a verifier can be written in another language from this page alone, without
importing the package. `BeamMCP.Connectome.Canonical` is one implementation of it; where the
two disagree, the page is right and the code is the defect.

Vocabulary is in `docs/connectome.md`. What is hashed is the **declared form** of a graph:
its schema version, the algorithm it is hashed with, its nodes and its edges. Weights are
not in it — a weight is a measurement, and the declared hash is a claim about wiring — and
travel in a separate **sidecar** that is never hashed with the declared bytes.

## Layout

The bytes are UTF-8 JSON with no insignificant whitespace, written under these rules:

1. **The top level is an object with exactly four members, in this fixed order:**
   `"schema_version"`, then `"algorithm"`, then `"nodes"`, then `"edges"`. This is the one
   place the order is fixed rather than sorted, so the version is the first thing a reader
   meets and the digest the second. The schema version is the integer `3` (see *Versions*
   below). The algorithm is one of the three strings `"sha256"`, `"sha384"`, `"sha512"` —
   the name under which the digest is known to `:crypto`, lowercase, no hyphen — and it is
   what rule 9 hashes the bytes with. **The nodes and edges members do not depend on the
   algorithm:** two envelopes of one graph under two digests differ in that member's value
   and in nothing else, so the bytes under another digest are derived from the bytes under
   one by changing that value alone (the worked example shows it), and the goldens
   `golden.sha384` and `golden.sha512` are the hashes of `golden.json` with the member so
   changed. A name outside the three is not a canonical form: the
   package refuses it at the option before writing a byte, and a verifier meeting one
   refuses the record rather than guessing a digest.
2. **`"nodes"` is an array sorted by `"id"`** — by the bytes of the UTF-8 id, which is the
   same as by code point. Each node is an object with exactly `"id"`, `"kind"`, `"labels"`,
   `"level"` — in that order, which is their sorted order.
3. **`"edges"` is an array sorted by the tuple** (`from`, `to`, `kind`, `provenance`), each
   compared as in rule 2, left to right. Each edge is an object with exactly `"from"`,
   `"kind"`, `"provenance"`, `"sign"`, `"to"` — in that order, which is their sorted order.
   **No weight.** That tuple is an edge's identity: `BeamMCP.Connectome.Graph.new/1` refuses
   two edges with the same tuple and an edge whose `from` or `to` names no node, so the
   canonical form never meets either; it neither merges nor drops. The sign is not part of
   the identity — one edge carries one sign. A graph struct built by literal, bypassing
   `BeamMCP.Connectome.Graph.new/1`, is read against the same refusals before a byte is written
   (`BeamMCP.Connectome.Graph.check/1`) and refused as `{:invalid_graph, reason}` under the
   graph's own name for the fault.
4. **Every other object** — `"labels"` and anything nested in it — **sorts its keys by UTF-16
   code unit**, the order [RFC 8785](https://www.rfc-editor.org/rfc/rfc8785) (the JSON
   Canonicalization Scheme) uses. For keys within the Basic Multilingual Plane this is code
   point order; a key containing a character above U+FFFF sorts by its surrogate pair, so
   for example U+1F600 sorts before U+FF01.
5. **Every atom is a string under the name of its field.** `kind`, `level`, `sign` and
   `provenance` are written as their name: `"kind":"module"`, `"level":"module"`. A reader
   tells the family by the key alone; no value is ever a bare, unnamed word. A label key may
   arrive as an atom or a string and is written as the same string either way; the three
   atoms `nil`, `true` and `false` are the JSON literals `null`, `true` and `false` as
   values, and are refused as keys.
6. **Strings are NFC-normalised** before anything else — ids, edge endpoints, label keys and
   label values, whether they arrived as strings or as atoms. NFC, not NFKC: canonical
   equivalents fold (a combining sequence and its precomposed form, U+212B and U+00C5), and
   compatibility equivalents stay distinct (`ﬁ` U+FB01 and `fi` are two strings). Two nodes
   whose ids coincide after normalisation are refused, never merged; so are two label keys in
   one object that coincide after normalisation, or an atom and a string spelling one key.
   **A string that is not well-formed UTF-8 is refused** — well-formed as Unicode defines it:
   no overlong form, no encoded surrogate, nothing past U+10FFFF, no truncated sequence;
   noncharacters such as U+FFFE and a byte-order mark are well-formed and written literally.
   The refusal names the node and the field for an id or a top-level label; inside a nested
   value it is reported as rule 8 says, by the label and its whole value. It is refused
   because it has no canonical bytes: a writer that stops at the bad byte would emit a
   prefix, and two distinct strings could meet. NFC is applied with the Unicode tables of
   the runtime that encodes; Unicode's normalisation stability policy keeps the result the
   same for every character assigned in both runtimes' versions, so two runtimes differ only
   on a string carrying a code point one of them does not yet know.
7. **String escaping** is RFC 8785's: `"` as `\"`, `\` as `\\`, and the control characters
   U+0008, U+0009, U+000A, U+000C, U+000D as `\b`, `\t`, `\n`, `\f`, `\r`; every other
   character below U+0020 as `\u` followed by four lowercase hexadecimal digits; **everything
   else literal UTF-8**, including `/`, U+007F, U+2028 and U+2029, and every character above
   U+FFFF as its own UTF-8 bytes, never as a surrogate pair.
8. **Label values** are strings, integers, `true`, `false`, `null`, arrays of these, or
   objects of these (sorted by rule 4). An atom label value is written as a string. Integers
   are decimal with no sign for zero or positive values, a leading `-` for negative ones, no
   leading zeros, no exponent, and no upper bound: an integer beyond 2^53 is written in full,
   and a reader that cannot hold it exactly cannot re-derive the bytes — that is the reader's
   limit, stated here rather than rounded. An empty object is `{}` and an empty array `[]`.
   **A float is refused**, because two runtimes may print it differently; so is anything with
   no byte form (a reference, a pid, a tuple, a function), and a struct — a struct is not a
   labels map, and its fields are the private layout of another module, which a release may
   change. A refusal at any depth is reported by node, by the label it was met under, and by
   that label's whole value.
9. **The hash is the digest the bytes name, over exactly these bytes:** SHA-256 for
   `"algorithm":"sha256"` (32 bytes; sixty-four lowercase hexadecimal characters when
   written as text), SHA-384 for `"sha384"` (48 bytes; ninety-six), SHA-512 for `"sha512"`
   (64 bytes; one hundred and twenty-eight). The algorithm member is part of the bytes, so
   it is under the hash: two envelopes of the same graph that name different digests are
   different bytes with different hashes, and neither is a rewrite of the other. A verifier
   reads the version first, then the algorithm, then hashes — it never chooses a digest the
   bytes do not name, and it treats a name it does not know as a malformed record. SHA-256 is
   the default the package writes when the caller names none, and stays the default
   indefinitely; the other two are a caller's option (`algorithm:` on
   `BeamMCP.Connectome.Canonical.encode/2`, `hash/2`, `hash_hex/2`, `hash_value/2` and
   `to_json/2`), never a constant of a release.

## Worked example

A server `"s"` with one tool `"t"` (labelled `mode: :read_only`) and the one declared edge
from the server to the tool. Its canonical bytes under the default algorithm, on one line:

```json-canonical
{"schema_version":3,"algorithm":"sha256","nodes":[{"id":"s/server","kind":"server","labels":{},"level":"server"},{"id":"s/tool/t","kind":"tool","labels":{"mode":"read_only"},"level":"server"}],"edges":[{"from":"s/server","kind":"invoke","provenance":"declared","sign":"unset","to":"s/tool/t"}]}
```

sha256: `a401cd47f0f0410d17248538eb8a3ef00018f6a31bf6fb6a7b9b0ba3377f570e`

Reproduce it without the package: paste the line above into a file with no trailing newline
and run `sha256sum` over it, or `printf '%s' '<the line>' | sha256sum`.

The same graph under SHA-384 is a different envelope — one member differs — and so a
different hash, over the bytes that name it:

```json-canonical-sha384
{"schema_version":3,"algorithm":"sha384","nodes":[{"id":"s/server","kind":"server","labels":{},"level":"server"},{"id":"s/tool/t","kind":"tool","labels":{"mode":"read_only"},"level":"server"}],"edges":[{"from":"s/server","kind":"invoke","provenance":"declared","sign":"unset","to":"s/tool/t"}]}
```

sha384: `f5b9b2f4fe21a4bfe88721d804f4f82d167f73f7dd59b1a64ae0196f4cf78f05a6b9a3efa6d02e7362469796dbba53dd`

(`sha384sum` over that line.) Under SHA-512 the member reads `"algorithm":"sha512"` and the
rest of the line is byte-identical:

sha512: `26cacb025eeaeabb0c441a293882ab81ec2436b80559618fd700dc494f9a5d2e2c6d46cee69a68cbdc84746aa9d64a4a11da027df7b0bc733ba1091031ee2e78`

A blind reader reproduces all three from this page alone: rule 1 fixes the four members and
their order, rule 9 the digest by the member's value, and the line is the same in every
byte but that value.

## Versions

`schema_version` names the vocabulary the bytes were written in and, from `3`, the shape of
the envelope. **`1`** (0.4.0): the sign values were `allow`, `deny`, `hold`, `unknown`.
**`2`** (0.5.0): `unset` — no sign was supplied to the package that wrote the bytes — and
`ungoverned`, a consumer's affirmative "no rule of my policy applies", replace `unknown`;
nothing else moved. **`3`** (`0.6.0`, which carries this note): the envelope
names its algorithm as a fourth top-level member, `"algorithm"`, between the version and the
nodes (rule 1), and the hash is that digest over the bytes (rule 9). The vocabulary is `2`'s,
unchanged. **At `1`, `unknown` covers both of `2`'s new signs**: a 0.4.0 consumer that looked
at an edge and found nothing governing it had no `ungoverned` to write, so its honest value
was `unknown` too, and the bytes do not say which case a given `unknown` was. A reader must
not narrow a version-1 `unknown` to `unset`; it is "one of the two, unrecorded which".

**What a verifier holding bytes at `1` or `2` does** — 0.4.0 and 0.5.0 bytes exist in the
world, and their hashes stay verifiable forever under their own version: those bytes name no
algorithm, and **at `1` and `2` the digest is SHA-256**, by this rule and by no member of the
bytes; the verifier hashes the bytes it holds, unchanged, with SHA-256, and compares. It does
not add an `"algorithm"` member, rewrite the version, or re-encode: a `2` envelope with a
member inserted is different bytes with a different hash, not a migration. At `3` the
verifier reads the member and hashes with what it names; a `3` envelope without the member,
or a `1` or `2` envelope with one, is a malformed record and is refused. So the whole
verifier is: read `schema_version`; below `3`, SHA-256; at `3`, the named digest; anything
else, refuse. Published 0.4.0 and 0.5.0 hashes verify under that rule exactly as they did the
day they were written.

What the version tells the verifier beyond the digest is how to *read* the sign field: at
`1`, `unknown` is a valid sign and `ungoverned` is not; at `2` and `3`, `unset` and
`ungoverned` are valid and `unknown` is not. A reader that resolves the vocabulary by the
version it finds first (as Avro resolves a writer's schema against a reader's) needs no other
signal. A sign outside the vocabulary of the version the bytes name is a malformed record:
the hash still verifies (it is over the bytes), and the record is refused, never corrected —
the rule the package applies to itself in `BeamMCP.Connectome.Graph.new/1`. The package itself
writes `3` and only `3`, and `BeamMCP.Connectome.Graph.new/1` refuses a graph carrying any
other version rather than translating it: bytes are not re-imported here, only produced and
hashed. `test/fixtures/connectome/golden.v2.json` and `golden.v2.sha256` are 0.5.0's goldens
kept as they were, and a test verifies them the way this section says.

## The sidecar

Weights are written separately as `{"schema_version":3,"weights":[…]}` — the graph's version, no algorithm member, since the sidecar is never hashed —, one object per edge
that carries a weight, each with `"from"`, `"kind"`, `"provenance"`, `"to"`, `"weight"` in
that order, the array sorted as in rule 3, the same string rules. An integer weight is an
integer; a float weight is written in the shortest form that round-trips
(`:erlang.float_to_binary/2` with `:short`, OTP 25's — every release this package compiles on
has it, the floor being OTP 27, and the placement below is measured on OTP 27, 28 and 29 by the
CI matrix). The digits are the shortest that round-trip; the
placement is Erlang's, which differs from other runtimes' shortest forms and is decided by
the digit count of the mantissa, not by the magnitude. Write the digits as D, a string with
no trailing zeros, of length L, and let e be the power of ten such that the value is
D × 10^e. Plain notation is used when −4 ≤ e ≤ 2 for a one-digit D, and when
−(L+2) ≤ e ≤ 1 otherwise (≤ 2 when e + L − 1 ≥ 10) — except that D ≥ 2⁵³ with e = 0,
D > 2⁵² div 5 with e = 1, and D > 2⁵¹ div 25 with e = 2 take an exponent. Plain notation
appends `.0` when no digit falls after the point, and prefixes `0.` and −(L+e) zeros when
L + e ≤ 0. Exponent notation is the first digit, `.`, the remaining digits or `0`, `e`, and
e + L − 1 with no `+` and no padding. Zero is `0.0`, and a negative zero — which the edge
constructor admits, as it is not below zero — is `-0.0`. So `0.1`, `0.0001`,
`999999999999999.0`, `1.0e15`, `1.0e-5`, `1.0e20`, `9.99e14`, `3.0e6`, `1.23456e-4`,
`0.001234`, `12340.0`, `0.0`, `-0.0`. The sidecar is not part of any hash. It is defined
only for a graph whose declared form encodes: what `encode/1` refuses, `sidecar/1` refuses
with the same reason.

## Signing the bytes

The bytes `encode/2` produces are the bytes a signer signs, and this package signs none of
them itself. The seam is `BeamMCP.Connectome.Canonical.signature/3`: it encodes the graph
with `encode/2` (the `:algorithm` option and nothing else read from the options), hands
exactly those bytes to a host-supplied module implementing `BeamMCP.Signer` — one callback,
`sign(canonical_bytes, opts)`, two arguments with those names, the options passed through as
the host gave them (a key, a key id: the signer's to read, never this package's) — and returns
`{:ok, %{algorithm: algorithm, signature: signature, signer: module}}`. **The envelope does
not move**: a signature is placed beside the bytes, never inside them, so every golden on
this page and every verifier that re-derives the digest is untouched by whether a signer
was attached. `BeamMCP.Signer.None`, the one implementation in this package, answers
`{:error, :no_signer}` and `signature/3` passes it on as `{:error, {:signer, :no_signer}}`; the
reference implementation that holds a key (Ed25519 through OTP's `:crypto`, the key under
`opts[:private_key]`) is the separate package `beam_mcp_signer`, which a host attaches. A census pins the callback's shape, the one `def sign` under `lib/`
and the one call site (`test/beam_mcp/boundary/no_signature_test.exs`), so the seam widens
only as a visible act.

## What the exports are

`to_json/2` is the canonical bytes, under the algorithm its option names. `to_dot/1` and `to_graphml/1` are renderings of the same
canonical order for Graphviz and GraphML readers: they carry kind, level, labels, edge kind,
provenance and sign, and no weight. They are not canonical forms and are not hashed.

DOT quotes every id and every value, and quotes a label's attribute name too (`"label_<key>"`),
because a key may carry `=`, a space or a quote; `kind`, `level` and the edge attributes are
DOT identifiers and stay bare. GraphML's schema types every id as an NMTOKEN; a node id is
not one (it carries `/`), and the export writes ids as given and renames nothing — a reader
that validates against the schema would reject them. Label keys are declared as `l0`, `l1`,
… in the order of rule 4 with `attr.name` carrying the key, so a key carrying a space or a
quote never lands in an id. Text is escaped: `&`, `<`, `>`, `"`, and
tab, LF and CR as the character references `&#9;`, `&#10;`, `&#13;` — a parser folds the
literal characters to a space inside an attribute value and CR to LF in content, and a
reference survives both, so two ids that differ only by whitespace kind stay two nodes. A
character outside XML 1.0's Char production — `#x9 | #xA | #xD | [#x20-#xD7FF] |
[#xE000-#xFFFD] | [#x10000-#x10FFFF]`, so a C0 control other than tab, LF and CR, or U+FFFE
or U+FFFF — which the canonical bytes do carry, is refused by `to_graphml/1` as
`{:not_xml, id, codepoint}` rather than written into a document every conforming parser
rejects; no character reference can carry it either.

There is no Cypher export, on purpose: the canonical bytes load into Neo4j as they are, with
APOC's JSON loader over the `nodes` array (`MERGE` on `id`) and the `edges` array (`MATCH`
the two ids, `MERGE` the relationship) — two statements the Livebook shows — and a fourth
rendering would be one more surface no hash covers.

The exports' exact bytes are not specified by this page. A label value that is not a string
is written as its rule-8 JSON text in both, so the string `"true"` and the boolean `true`
read the same there; everything else — headers, indentation, attribute order, DOT's own
escape of `\` and `"` — is the exporter's layout, which `test/fixtures/connectome/golden.dot`
and `golden.graphml` pin and a release may change without the hash changing.
