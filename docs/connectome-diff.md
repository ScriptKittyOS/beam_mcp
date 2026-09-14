<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# The diff: declared against observed

`BeamMCP.Connectome.Diff.run/3` takes the declared connectome and the observed one — two
`BeamMCP.Connectome.Graph` values — and a window the consumer supplies, and returns a
record: every edge of either graph in exactly one of four classes, and a coverage bound as
counts. The record has canonical bytes, written by the same rules as a node's labels, so a
consumer signs it with the verifier it already has. This page is the contract a consumer
can implement without importing the package; the worked example at the end reproduces
with `sha256sum` alone.

## Labels, not isomorphism

Two edges are the same edge if and only if their **label** — `from`, `to`, `kind` — is
equal. Ids are structural, derived by one function from the identity a host supplies
(`docs/connectome.md`, the id scheme), so the label is the whole identity of an edge and
provenance says only which graph it came from. The diff is a set difference over labels and
nothing more, and that is a decision, not an omission: a graph-isomorphism check is NP-hard
in general and would be wrong here besides — it would call two differently named tools "the
same" whenever their neighbourhoods matched. It is written down so nobody improves the diff
into one later.

## The four classes

| class | an edge whose label is | in the vocabulary |
| -- | -- | -- |
| `declared_and_observed` | in both graphs, and the signs are not both supplied and different | — |
| `declared_never_observed` | in the declared graph only | **dead authority** |
| `observed_but_undeclared` | in the observed graph only | a **drift finding** |
| `changed_sign` | in both, with a sign the consumer supplied on **both** sides — neither `unknown` — and the two differ | a **drift finding** |

A sign on one side only is not a change: the package never guesses what the missing one
would have been, so `allow` against `unknown` is `declared_and_observed`. Every label of
either input lands in exactly one class; the four classes partition the union of the labels.

## The coverage bound, as counts

A float has no canonical bytes, so the bound is integers, and the fractions are the
consumer's to divide:

| count | what it counts |
| -- | -- |
| `declared_edges` | edges in the declared graph |
| `observed_edges` | edges in the observed graph |
| `declared_and_observed` | labels in both — the two "in both" classes together |
| `declared_endpoint_covered` | declared edges whose `from` **and** `to` are both ids of observed nodes |
| `declared_nodes` | nodes in the declared graph |
| `observed_nodes` | nodes in the observed graph |
| `nodes_in_both` | node ids in both |

The three figures `docs/connectome.md` names as the coverage bound are ratios of these, and
they are three different figures, not one: **declared edges observed** is
`declared_and_observed / declared_edges`; **observed edges declared** is
`declared_and_observed / observed_edges`; **completeness** — the connectomics figure,
"synapses between fully proofread cells", transposed — is
`declared_endpoint_covered / declared_edges`: the share of declared authority whose both
ends the observation reached, whether or not the edge itself was seen. An edge counted
under `declared_endpoint_covered` may still be dead authority.

The **window** is the consumer's: any map in the label grammar (a start and an end as
strings, for one), carried into the record verbatim. The package never infers it; a diff
without a window is refused by name (`{:error, {:missing, :window}}`), and a window with no
canonical bytes with `{:error, {:uncanonical, _}}`. A graph a literal built wrong is refused
before it is compared, as `{:error, {:declared, reason}}` or `{:error, {:observed, reason}}`
with the reason `Graph.new/1` would have given.

## The bytes

The record is one object written by rule 4 of `docs/connectome-canonical.md` — the rules of a
node's `"labels"` object, applied to the whole record (`Canonical.encode_value/1`): keys in
UTF-16 code-unit order and unique after NFC, strings NFC, every atom a string under the name
of its field, integers as integers, arrays in the order given, nested objects the same way;
nothing else. Its keys, in the order the rule gives them:

- `"classes"` — an object with the four class names as keys, each an array of label objects
  `{"from","kind","to"}`; a `changed_sign` entry carries `"declared_sign"` and
  `"observed_sign"` too. Each array is sorted by `from`, then `to`, then `kind`, comparing
  UTF-16 code units, so equal inputs give equal bytes whatever order the graphs were built in.
- `"coverage"` — the seven counts.
- `"schema_version"` — `1`.
- `"window"` — the consumer's map.

Nothing else enters the record: no weight, no latency, no argument, no name the graphs did
not already carry. `Diff.hash/1` is SHA-256 over these bytes.

## Worked example

Server `srv`, tools `a`, `b`, `c` on both sides. Declared: `a→b`, `a→c`, `c→a` (sign
`allow`), `b→a` (sign `allow`). Observed: `a→b`, `b→c`, `c→a` (sign `deny`), `b→a` (sign
`unknown`). Window `{"ended_at": "2026-09-14T01:00:00Z", "started_at":
"2026-09-14T00:00:00Z"}`. The bytes (702 of them, one line):

```
{"classes":{"changed_sign":[{"declared_sign":"allow","from":"srv/tool/c","kind":"invoke","observed_sign":"deny","to":"srv/tool/a"}],"declared_and_observed":[{"from":"srv/tool/a","kind":"invoke","to":"srv/tool/b"},{"from":"srv/tool/b","kind":"invoke","to":"srv/tool/a"}],"declared_never_observed":[{"from":"srv/tool/a","kind":"invoke","to":"srv/tool/c"}],"observed_but_undeclared":[{"from":"srv/tool/b","kind":"invoke","to":"srv/tool/c"}]},"coverage":{"declared_and_observed":3,"declared_edges":4,"declared_endpoint_covered":4,"declared_nodes":4,"nodes_in_both":4,"observed_edges":4,"observed_nodes":4},"schema_version":1,"window":{"ended_at":"2026-09-14T01:00:00Z","started_at":"2026-09-14T00:00:00Z"}}
```

SHA-256: `3cd6a14676d47e104121e90981cfca920dafccb21743dd370ea39cb06df3c298`. The four
classes hold one label each but `declared_and_observed`, which holds two: `b→a` is there
because its observed sign is `unknown`, not supplied.

## What the diff does not do

It does not sign (the consumer's, through the seam a later slice names). It does not decide
what a finding means — drift is a record; what to do about it is the host's. It carries no
motif or rich-club figure and no re-approval state. It reads no weight: a weight is a
measurement in the observed sidecar, and the diff is about identity.
