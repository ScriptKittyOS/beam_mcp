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
its schema version, its nodes and its edges. Weights are not in it — a weight is a
measurement, and the declared hash is a claim about wiring — and travel in a separate
**sidecar** that is never hashed with the declared bytes.

## Layout

The bytes are UTF-8 JSON with no insignificant whitespace, written under these rules:

1. **The top level is an object with exactly three members, in this fixed order:**
   `"schema_version"`, then `"nodes"`, then `"edges"`. This is the one place the order is
   fixed rather than sorted, so the version is the first thing a reader meets. The schema
   version is the integer `1`.
2. **`"nodes"` is an array sorted by `"id"`** — by the bytes of the UTF-8 id, which is the
   same as by code point. Each node is an object with exactly `"id"`, `"kind"`, `"labels"`,
   `"level"` — in that order, which is their sorted order.
3. **`"edges"` is an array sorted by the tuple** (`from`, `to`, `kind`, `provenance`), each
   compared as in rule 2, left to right. Each edge is an object with exactly `"from"`,
   `"kind"`, `"provenance"`, `"sign"`, `"to"` — in that order, which is their sorted order.
   **No weight.** That tuple is an edge's identity: `BeamMCP.Connectome.Graph.new/1` refuses
   two edges with the same tuple and an edge whose `from` or `to` names no node, so the
   canonical form never meets either; it neither merges nor drops. The sign is not part of
   the identity — one edge carries one sign.
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
   prefix, and two distinct strings could meet. NFC is applied with the Unicode tables of the runtime that encodes; Unicode's
   normalisation stability policy keeps the result the same for every character assigned in
   both runtimes' versions, so two runtimes differ only on a string carrying a code point one
   of them does not yet know.
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
9. **The hash is SHA-256 over exactly these bytes**, written as sixty-four lowercase
   hexadecimal characters when written as text.

## Worked example

A server `"s"` with one tool `"t"` (labelled `mode: :read_only`) and the one declared edge
from the server to the tool. Its canonical bytes, on one line:

```json-canonical
{"schema_version":1,"nodes":[{"id":"s/server","kind":"server","labels":{},"level":"server"},{"id":"s/tool/t","kind":"tool","labels":{"mode":"read_only"},"level":"server"}],"edges":[{"from":"s/server","kind":"invoke","provenance":"declared","sign":"unknown","to":"s/tool/t"}]}
```

sha256: `53c20fb1efc7a179be40e9edea9c37704102619789961af2385b5bf8b0834643`

Reproduce it without the package: paste the line above into a file with no trailing newline
and run `sha256sum` over it, or `printf '%s' '<the line>' | sha256sum`.

## The sidecar

Weights are written separately as `{"schema_version":1,"weights":[…]}`, one object per edge
that carries a weight, each with `"from"`, `"kind"`, `"provenance"`, `"to"`, `"weight"` in
that order, the array sorted as in rule 3, the same string rules. An integer weight is an
integer; a float weight is written in the shortest form that round-trips (`:erlang.float_to_binary/2`
with `:short`, which OTP 25 introduced). The sidecar is not part of any hash. It is defined
only for a graph whose declared form encodes: what `encode/1` refuses, `sidecar/1` refuses
with the same reason.

## What the exports are

`to_json/1` is the canonical bytes. `to_dot/1` and `to_graphml/1` are renderings of the same
canonical order for Graphviz and GraphML readers: they carry kind, level, labels, edge kind,
provenance and sign, and no weight. They are not canonical forms and are not hashed.
