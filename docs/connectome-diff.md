<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# The diff: declared against observed

`BeamMCP.Connectome.Diff.run/3` takes the declared connectome and the observed one (two
`BeamMCP.Connectome.Graph` values) and a window the consumer supplies, and returns a
record: every edge of either graph in exactly one of four classes, and a coverage bound as
counts. The record has canonical bytes, written by the same rules as a node's labels, so a
consumer signs it with the verifier it already has. This page is the contract a consumer can
implement without importing the package; the worked example at the end reproduces with
`sha256sum` alone.

## Labels, not isomorphism

Two edges are the same edge if and only if their **label** (`from`, `to`, `kind`) is
equal, compared as the encoder writes them: **after NFC** (rule 6 of
`docs/connectome-canonical.md`). Ids are structural, derived by one function from the
identity a host supplies (`docs/connectome.md`, the id scheme; `srv/server` for the server
node, `srv/tool/a` for a tool), so the label is the whole identity of an edge and provenance
says only which graph it came from. Two inputs are admitted only as the encoder would admit
them: a graph whose ids coincide after NFC has no canonical bytes and so no diff (refused
as `{:error, {:declared, {:uncanonical, {:duplicate_id_after_nfc, id}}}}` or the observed
mirror), and a graph carrying an edge of the other side's provenance is refused as `{:error,
{:declared, {:invalid, :provenance, :observed}}}` or the mirror, so on every admitted input
an edge and a label are the same count. The diff is a set difference over labels and nothing
more, and that is a decision, not an omission: a graph-isomorphism check is NP-hard in
general and would be wrong here besides; it would call two differently named tools "the
same" whenever their neighbourhoods matched. It is written down so nobody improves the diff
into one later.

## The four classes

| class | an edge whose label is | in the vocabulary |
| -- | -- | -- |
| `declared_and_observed` | in both graphs, and the signs are not both supplied and different | none |
| `declared_never_observed` | in the declared graph only | **dead authority** |
| `observed_but_undeclared` | in the observed graph only | a **drift finding** |
| `changed_sign` | in both, with a sign the consumer supplied on **both** sides (neither `unset`) and the two differ: two authorities disagree | a **drift finding** |

A sign on one side only is not a change: `unset` is abstention, not a verdict, and the package
never guesses what the missing one would have been, so `allow` against `unset` is
`declared_and_observed`: a sign was acquired, not changed. `ungoverned` is a supplied value,
so `ungoverned` against `deny` *is* changed-sign, and `unset` against `ungoverned` is not. The
standalone case, `unset` on both sides, never produces a finding. Every label of either input
lands in exactly one class; the four classes partition the union of the labels, and the sign
never moves a label between classes: an observed edge nobody declared is drift whatever its
sign, and a declared `ungoverned` edge is recorded like any other.

## The coverage bound, as counts

A float has no canonical bytes, so the bound is integers, and the fractions are the
consumer's to divide:

| count | what it counts |
| -- | -- |
| `declared_edges` | edges in the declared graph |
| `observed_edges` | edges in the observed graph |
| `declared_and_observed` | labels in both: the two "in both" classes together |
| `declared_endpoint_covered` | declared edges whose `from` **and** `to` are both ids of observed nodes |
| `observed_endpoint_declared` | observed edges whose `from` **and** `to` are both ids of declared nodes |
| `declared_nodes` | nodes in the declared graph |
| `observed_nodes` | nodes in the observed graph |
| `nodes_in_both` | node ids in both |
| `declared_sign_only` | labels in both with a sign supplied on the declared side and `unset` on the observed: signed at configuration time, unsigned in the run (the odder direction, so it is its own count) |
| `observed_sign_only` | labels in both with a sign supplied on the observed side and `unset` on the declared: an authority spoke during the run about an edge nobody had signed at configuration time |

The coverage bound `docs/connectome.md` defines ("the measured fraction of one graph the
other accounts for, stated with the window") is made of these figures, and they are
different figures, not one:

- **declared edges observed**: `declared_and_observed / declared_edges`.
- **observed edges declared**: `declared_and_observed / observed_edges`.
- **completeness**: `observed_endpoint_declared / observed_edges`. This is the
  connectomics figure, "synaptic completeness: the fraction of synapses between fully
  proofread cells", with its roles kept: the population is what the measurement found
  (every observed edge, declared or not, as every detected synapse is counted whether or
  not a curated cell claims it) and the condition is membership of both ends in the curated
  set: here, the declaration. "Proofread cell" maps to "declared node"; "detected synapse"
  to "observed edge". An observed edge nobody declared still counts when it ran between
  declared parts; an edge that ran wholly outside the declared parts counts against it,
  and no other figure tells those two apart: both are `observed_but_undeclared`, and both
  lower "observed edges declared" the same.
- **endpoint coverage**: `declared_endpoint_covered / declared_edges`, the dual, with the
  roles swapped: how much of the declaration sits where the window reached at all. An
  observed node here is one that appeared as an endpoint of at least one observed edge in
  the window, nothing more; an edge counted under `declared_endpoint_covered` may still be
  dead authority. A label in both graphs has both ends in both, so
  `declared_and_observed ≤ declared_endpoint_covered ≤ declared_edges` and
  `declared_and_observed ≤ observed_endpoint_declared ≤ observed_edges` always: each
  endpoint figure is a ceiling on the shared count, which is why it is a *bound*.

(The first draft of this page called the dual "completeness"; a review lane implementing the
definitions from the page found the roles swapped. Elsewhere in the package,
`BeamMCP.Connectome.Declared.Bound` is "the completeness bound" of the *declared* build (an
enumeration of what static analysis could not see), a different thing from this fraction.)

The **window** is the consumer's, any map in the label grammar: string or atom keys (an
atom is written as its name), nested maps, lists, integers, booleans, `null`; an empty map
is allowed and written `{}`. It is carried into the record verbatim, and so is its size: the
record is at least as large as the window, and the window is encoded twice: once at
`run/3`, to refuse one with no canonical bytes early, and once at `encode/1` (measured: a 1
MB window costs ~55 ms at each). Nothing in the package bounds it; a consumer that signs
records bounds its own windows. The package never infers it; a diff without a window is
refused by name (`{:error, {:missing, :window}}`), and a window with no canonical bytes (a
float inside, a struct, a keyword list, two keys that coincide after NFC) as `{:error,
{:uncanonical, {:label_value, "record", :window, value}}}`. The options themselves must be a
keyword list carrying `window:` and nothing else (`{:error, {:invalid, :opts, given}}` for
another shape, `{:error, {:invalid, :opts, [key, ...]}}` for a key the function does not
take; a typo is not "no window"). Refusals are answered in a fixed order: the options, then
the declared graph, then the observed graph, then the window; the first refusal found is
the one returned. A graph a literal built wrong is refused before it is compared, as
`{:error, {:declared, reason}}` or `{:error, {:observed, reason}}` with the reason
`BeamMCP.Connectome.Graph.new/1` would have given.

## The bytes

The record is one object written by rule 4 of `docs/connectome-canonical.md`, the rules of
a node's `"labels"` object, applied to the whole record (`BeamMCP.Connectome.Canonical.encode_value/1`): keys
in UTF-16 code-unit order and unique after NFC, strings NFC, every atom a string under the
name of its field, integers as integers, arrays in the order given, nested objects the same
way; nothing else. Its keys, in the order the rule gives them:

- `"algorithm"`: the digest the record is hashed with, `"sha256"` unless the caller chose
  `"sha384"` or `"sha512"` (`algorithm:` on `BeamMCP.Connectome.Diff.encode/2` and `hash/2`;
  rule 9 of `docs/connectome-canonical.md`, the same three names). The keys sort, so it is
  the first member a reader meets; it is under the hash like every other.
- `"classes"`: an object with the four class names as keys, each an array of label objects
  `{"from","kind","to"}` (an empty class is `[]`); a `changed_sign` entry carries
  `"declared_sign"` and `"observed_sign"` too. Each array is sorted by `from`, then `to`,
  then the kind's name, comparing UTF-16 code units, so equal inputs give equal bytes
  whatever order the graphs were built in.
- `"coverage"`: the ten counts (eight since 0.4.0; the two one-sided sign counts since 0.5.0).
- `"schema_version"`: `3` (the record's own axis: bumped to `2` in 0.5.0 when changed-sign
  excluded `unset` by name and two counts were added, and to `3` in 0.6.0 when
  the algorithm joined the bytes; `1` and `2` records carry the earlier semantics, name no
  algorithm, and are SHA-256 over their bytes; a verifier reads the version first and
  hashes `1` and `2` records with SHA-256 exactly as before, as the canonical page's
  *Versions* section says for the graph).
- `"window"`: the consumer's map.

Nothing else enters the record: no weight, no latency, no argument, no label, no name the
graphs did not already carry, and every name they do carry is in it: a tool's, a module's,
a registered process's name is identity and is published, as `docs/connectome-observed.md`
says; a secret in a name is published here too. `hash/1` encodes and hashes; a consumer that
wants both the bytes and the hash hashes the bytes it already holds rather than paying the
encode twice. `BeamMCP.Connectome.Diff.hash/2` is the digest the bytes name over these bytes: the raw
32, 48 or 64; `BeamMCP.Connectome.Diff.hash_hex/2` is the same as lowercase hexadecimal, the form this page
writes it in.

## Worked example

Server `srv`, tools `a`, `b`, `c` on both sides. Declared: `a→b`, `a→c`, `c→a` (sign
`allow`), `b→a` (sign `allow`). Observed: `a→b`, `b→c`, `c→a` (sign `deny`), `b→a` (sign
`unset`). Window `{"ended_at": "2026-09-14T01:00:00Z", "started_at":
"2026-09-14T00:00:00Z"}`. The bytes (800 of them, one line):

```
{"algorithm":"sha256","classes":{"changed_sign":[{"declared_sign":"allow","from":"srv/tool/c","kind":"invoke","observed_sign":"deny","to":"srv/tool/a"}],"declared_and_observed":[{"from":"srv/tool/a","kind":"invoke","to":"srv/tool/b"},{"from":"srv/tool/b","kind":"invoke","to":"srv/tool/a"}],"declared_never_observed":[{"from":"srv/tool/a","kind":"invoke","to":"srv/tool/c"}],"observed_but_undeclared":[{"from":"srv/tool/b","kind":"invoke","to":"srv/tool/c"}]},"coverage":{"declared_and_observed":3,"declared_edges":4,"declared_endpoint_covered":4,"declared_nodes":4,"declared_sign_only":1,"nodes_in_both":4,"observed_edges":4,"observed_endpoint_declared":4,"observed_nodes":4,"observed_sign_only":0},"schema_version":3,"window":{"ended_at":"2026-09-14T01:00:00Z","started_at":"2026-09-14T00:00:00Z"}}
```

SHA-256: `a8a4206fb65febc83ed099be8b7408b6938795efc8a92f7cac1f53781c4312e1`. Under `algorithm: :sha384`
the first member reads `"algorithm":"sha384"`, the rest of the line is byte-identical, and
SHA-384: `2efccb9b6852b3d4088b170987fd7e51c52d474a81522e3203d9420eda199fd2d872aebbd1e60e44b5c9b2b1e0b0090e`. The four
classes hold one label each but `declared_and_observed`, which holds two: `b→a` is there
because its observed sign is `unset`, not supplied.

## What the diff does not do

It does not sign (the consumer's, through the seam a later slice names). It does not decide
what a finding means: drift is a record; what to do about it is the host's. It carries no
motif or rich-club figure and no re-approval state. It reads no weight: a weight is a
measurement in the observed sidecar, and the diff is about identity.
