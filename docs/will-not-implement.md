<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# What this package will not implement

This page is the package's boundary, written down so that it survives the issue tracker. Each
entry below is something `beam_mcp` will never do, with the reason in a line and the test that
enforces it, by path and by name. **The tests are the proof; this page is the contract.** A
request to cross one of these lines is a request for a different package — a host, or a signer
— and will be answered by pointing here, not by widening this one.

The page and the tests are held together mechanically, in both directions, by three tests
(a citation is a path and, on the same line, the names it holds):
`test/beam_mcp/will_not_implement_test.exs` "every test the page cites exists, by path and by name, and every citation names a test" "every test file carrying a boundary marker is cited on the page" "every file under test/beam_mcp/boundary/ carries the marker".
Neither may drift from the other.

## How the censuses read the tree

A **census** is a test over the source rather than over behaviour. The boundary censuses share
one reader (`test/support/beam_mcp/boundary.ex`): every non-comment line of every `lib/**/*.ex`
file — the same files `mix compile` reads, so an untracked module is seen; doc strings are read
too, so a census that must allow prose says so by pattern. Each census was shown red by planting
its violation under `lib/` and restoring; the plants are in the repository's records, not in the
package. A census reads text, so its reach is the reach of its pattern; where a pattern allows a
shape, the entry says which.

## The entries

| # | The package will never | Why | Enforced by |
| -- | -- | -- | -- |
| 1 | **compute or populate a sign.** `:allow`, `:deny` and `:hold` are the host's; the package writes `:unknown` into every edge's sign slot, on both graphs. | A sign is a verdict. The package exports topology and lets the verdict be somebody else's, so that nothing in it can be mistaken for approval. | `test/beam_mcp/connectome/census_test.exs` "no code line under lib/ writes or names a sign other than :unknown"; `test/beam_mcp/readme_claims_test.exs` "the package writes only :unknown into the sign slot, on both graphs" |
| 2 | **hold a key.** No line under `lib/` generates, loads, decodes or stores key material. The one cryptographic call in the package is `:crypto.hash/2`, a digest over bytes with no key in it. | A package that holds a key can be asked to use it. The canonical bytes exist so that a consumer can sign them without importing this package. | `test/beam_mcp/boundary/no_key_holding_test.exs` "no line under lib/ names key material or calls a crypto function other than :crypto.hash/2" |
| 3 | **make a signature.** No signing or MAC primitive is called under `lib/`, and no function named `sign` is defined there. | Signing canonical bytes belongs to a separate package with one callback, `sign(canonical_bytes, opts)` — decided, not built. The `sign` field an edge carries is the host's verdict slot (entry 1), a value and not an act. | `test/beam_mcp/boundary/no_signature_test.exs` "no line under lib/ calls a signing or MAC primitive or defines a sign function" |
| 4 | **decide authority.** No verdict, no approval, no receipt, no risk tier, no egress masking. | These are the consumer's side of the boundary the project chose on its first day; the package exists partly to keep them there. The word "authority" itself is not in the census: under `lib/` it names the diff's own class, *dead authority* — a term the package defines, not an act it performs. The acts are the words barred. | `test/beam_mcp/readme_claims_test.exs` "deliberately out: no line under lib/ names a receipt, an approval, a risk tier or egress" |
| 5 | **put a payload byte into the observed graph.** Edge identity only: never an argument, a result, a header, an error message or a stack frame's contents. | A wiring diagram that carries payloads is a log, and a log of tool calls is the most sensitive artefact a host produces. The observed graph is safe to export because it cannot contain what was said. | `test/beam_mcp/connectome/observed_test.exs` "a marker in a nested argument map and in a uri argument is absent from rows, bytes, sidecar and latency" "a marker in the error a dispatch returns is absent" "a marker in an exception a dispatch raises is absent, and the edge was still recorded" "the :stop event itself carries no argument, result or header bytes" "dispatch_opts never enter: a secret handed to every dispatch is in no row, byte or summary" "request headers carrying the marker reach neither the events nor the rows" "a throw and an exit from the dispatch are exceptions of their kind, with marker-free frames; a crafted error_info is dropped from the frames"; `test/beam_mcp/connectome/tracer_test.exs` "a registered name is identity: a secret in a name is published in the bytes, the message beside it is not"; `test/beam_mcp/connectome/diff_test.exs` "an observed graph the collector built from a call carrying a marker diffs to bytes with no marker"; `test/beam_mcp/readme_claims_test.exs` "the observed graph carries edge identity only, never a payload byte" |
| 6 | **claim an MCP capability the specification does not define.** No topology or reachability capability on the wire; `connectome://` is the package's own URI scheme, not a claimed capability. | Capabilities are negotiated with clients that read the specification, not this README. An invented key is a promise no client can act on. The advertised keys are held to `ServerCapabilities` as each revision's schema defines it (`tasks` in 2025-11-25; `extensions` in 2026-07-28). | `test/beam_mcp/boundary/no_invented_capability_test.exs` "server/discover advertises only keys the 2026-07-28 schema defines" "the initialize result advertises only keys the 2025-11-25 schema defines" "no line under lib/ names a topology or reachability capability on the wire" |
| 7 | **issue or honour a session identifier.** Over HTTP no response carries `Mcp-Session-Id`, a request carrying one is answered exactly as one that does not, and no line under `lib/` reads or writes one. | Every request stands alone; the 2026-07-28 transport removed sessions, and the package does not reintroduce them by another name. Refusing unestablished callers on a transport where that matters is the host's job, stated in the README. | `test/beam_mcp/boundary/no_session_test.exs` "no response carries an mcp-session-id header, and a request carrying one is answered as if it did not" "no code line under lib/ reads or writes a session identifier" |
| 8 | **carry OAuth.** No authorization flow, discovery document, token endpoint or bearer handling under `lib/`. The transport offers `:authorize` and `:authorize_body` hooks and performs no cryptography. | Verifying is the host's work; making it possible is the transport's. A package that performs no cryptography (entries 2 and 3) cannot honestly offer an OAuth server. | `test/beam_mcp/boundary/no_oauth_no_client_test.exs` "no OAuth under lib/" |
| 9 | **be a client.** No module under `lib/` names itself a client, opens an outbound connection, or sends an `initialize` request; every `initialize` under `lib/` is a clause head that receives one, or the list of methods the modern era removed. | This is a server core. A client is a different package with a different threat model. | `test/beam_mcp/boundary/no_oauth_no_client_test.exs` "no client under lib/: no client module, no outbound connection, initialize only ever received" |
| 10 | **enumerate all paths or match motifs in the connectome.** `all_paths` is refused by name, always; it is not capped. | The number of paths is exponential in the graph; a cap would be a promise to answer "some of them", which is worse than no answer. The reachability questions the package does answer are on the reach page. | `test/beam_mcp/connectome/reach_test.exs` "all-paths enumeration is refused by name, not attempted" |
| 11 | **hold a tool, a domain, or a concrete catalog.** No module under `lib/` implements `BeamMCP.Catalog`, and no line under `lib/` builds a `%BeamMCP.ToolSpec{}` — the struct is defined there, matched there, and never constructed there. The catalog and the dispatch are injected by the host. | The thesis: a commodity protocol layer with nothing of its own to protect or to sell. | `test/beam_mcp/boundary/no_catalog_test.exs` "no module under lib/ implements BeamMCP.Catalog" "no line under lib/ constructs a tool"; `test/beam_mcp/catalog_test.exs` "what tools/list advertises is exactly what tools/call will accept" |

## What a census does not prove

Every entry above is proven by a test over this tree; none rests on reading alone. But a census
reads text, and text has edges worth stating:

- The censuses bar the acts by their names in Erlang and Elixir (`:crypto.sign`, `:public_key.`,
  `:httpc.`, `Mcp-Session-Id`, and so on). A dependency that performed one of these acts under
  another name would not be seen by the census; it would be seen by the dependency list, which is
  two packages (`jason`, `telemetry`) plus the optional `plug` and `bandit`, and by the gate's
  optional-deps step.
- Entry 7's wire half is asserted over the HTTP transport, the only transport with headers. Over
  stdio there is no header to carry a session identifier; the source half covers both.
- Entry 9's "sends no `initialize`" is a statement about this package's source. A host that wraps
  it and sends one is a client of something else, and out of this page's reach.

## Related

- The README's *Deliberately out* paragraph, which points here.
- The connectome pages: the [reach page](connectome-reach.md) states which questions the package
  answers and that `all_paths` is refused; the [observed page](connectome-observed.md) states the
  tracer's threat model and the payload rule.
