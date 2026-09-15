<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# What this package will not implement

This page is the package's boundary, written down so that it survives the issue tracker. Each
entry below is something `beam_mcp` will never do, with the reason in a line and the test that
enforces it, by path and by name. **The tests are the proof; this page is the contract.** A
request to cross one of these lines is a request for a different package: the *host* — the
application that embeds this package, supplies its catalog and dispatch function, and owns
every decision about them — for entries 1, 4, 7 and 11; a *signer*, a separate package with
one callback over the canonical bytes, decided and not yet written, for entries 2 and 3; a
client, a logger, an authorization server or a graph-mining library that this project will not
write, for entries 9, 5, 8 and 10; and for entry 6, the specification itself, since only it can
define a capability. Such a request is answered by pointing here, not by widening this package.

The page and the tests are held together mechanically, in both directions, by three tests
(a citation is a path and, on the same line, the names it holds):
`test/beam_mcp/will_not_implement_test.exs` "every test the page cites exists, by path and by name, and every citation names a test" "every test file carrying a boundary marker is cited on the page" "every file under test/beam_mcp/boundary/ carries the marker".
Neither may drift from the other.

## How the censuses read the tree

A **census** is a test over the source rather than over behaviour. The censuses under
`test/beam_mcp/boundary/` — entries 2, 3, 4, 6, 7, 8, 9, 10 and 11 — share one reader
(`test/support/beam_mcp/boundary.ex`): every non-comment line of every `lib/**/*.ex` file, the
same files `mix compile` reads, so an untracked module is seen; doc strings are read too, so a
census that must allow prose says so by pattern. That `lib/**/*.ex` is the whole application is
itself pinned, in the source and in the built artefact: `test/beam_mcp/boundary/population_test.exs` "nothing compiles into the application from outside lib/: no Erlang sources, no other elixirc path" "every module the built application lists is a BeamMCP module".
Two older censuses cited below read the tracked files instead (`git`): entry 1's sign census and
the README's word census under entry 4 — a module not yet added to git is outside their count,
which every file in a pull request is inside. Each census was shown red, before it was
committed, by planting its violation under `lib/` and restoring. A census reads text, so its
reach is the reach of its pattern; where a pattern allows a shape, the entry says which. That
nothing under `lib/` evaluates code or builds a module, function or atom at runtime — by the
names Elixir and Erlang give those acts: `apply`, `Code.eval_*`, `Code.compile_*`,
`Module.create`, `Module.concat`, `Function.capture`, `make_fun`, `binary_to_term`, the
`to_atom` family, with the one allowance of the argument-key atoms `BeamMCP.Server` reads from a
tool's declared schema — is pinned by the same kind of census, with the same reach:
`test/beam_mcp/boundary/no_dynamic_evaluation_test.exs` "no line under lib/ evaluates code or builds a name at runtime, beyond the argument-key atoms".
A barred name spelled by joining two strings is outside that census and every other; it is not
pinned, and the edges section says so.

## The entries

| # | The package will never | Why | Enforced by |
| -- | -- | -- | -- |
| 1 | **compute or populate a sign.** `:allow`, `:deny` and `:hold` are the host's; the package writes `:unknown` into every edge's sign slot, on both graphs. | A sign is a verdict. The package exports topology and lets the verdict be somebody else's, so that nothing in it can be mistaken for approval. | `test/beam_mcp/connectome/census_test.exs` "no code line under lib/ writes or names a sign other than :unknown"; `test/beam_mcp/readme_claims_test.exs` "the package writes only :unknown into the sign slot, on both graphs" |
| 2 | **hold a key.** No line under `lib/` generates, loads, decodes or stores key material. The one cryptographic function the package calls is `:crypto.hash/2`, a digest with no key in it — two sites, both SHA-256 over canonical bytes, and the count is pinned so that a third site has to say what it hashes. | A package that holds a key can be asked to use it. The canonical bytes exist so that a consumer can sign them without importing this package. | `test/beam_mcp/boundary/no_key_holding_test.exs` "no line under lib/ names key material or calls a crypto function other than :crypto.hash/2" ":crypto.hash/2 is called at two sites, both over canonical bytes" |
| 3 | **make a signature.** No signing or MAC primitive is called under `lib/`, and no function named `sign` is defined there. | Signing canonical bytes belongs to a separate package with one callback, `sign(canonical_bytes, opts)` — decided, not built. The `sign` field an edge carries is the host's verdict slot (entry 1), a value and not an act. | `test/beam_mcp/boundary/no_signature_test.exs` "no line under lib/ calls a signing or MAC primitive or defines a sign function" |
| 4 | **decide authority.** It writes no verdict (entry 1: the sign slot is only ever `:unknown`) and names no receipt (a signed record that a call happened), no approval (a decision that a call may proceed), no risk tier (a ranking of calls by consequence), no egress and no mask (the withholding or rewriting of what leaves the system) — any word containing *receipt*, *approv* or *egress*, any word beginning *tier* or *mask*. | Every one of these is a decision about the host's tools, and the package holds none of them; the moment it held one, its topology could be mistaken for a verdict. The words "verdict" and "authority" are not barred: under `lib/` they name the host's slot in the edge's docs and the diff's own class, *dead authority* — terms the package defines, not acts it performs. The acts are barred in the spellings code uses as well as prose. | `test/beam_mcp/boundary/no_authority_test.exs` "no line under lib/ names a receipt, an approval, a risk tier, egress or a mask, in any spelling"; `test/beam_mcp/connectome/census_test.exs` "no code line under lib/ writes or names a sign other than :unknown"; `test/beam_mcp/readme_claims_test.exs` "deliberately out: no line under lib/ names a receipt, an approval, a risk tier or egress" |
| 5 | **put a payload byte into the observed graph.** Edge identity only: never an argument, a result, a header, an error message or a stack frame's contents. | A wiring diagram that carries payloads is a log, and a log of tool calls is the most sensitive artefact a host produces. The observed graph is safe to export because it cannot contain what was said. | `test/beam_mcp/connectome/observed_test.exs` "a marker in a nested argument map and in a uri argument is absent from rows, bytes, sidecar and latency" "a marker in the error a dispatch returns is absent" "a marker in an exception a dispatch raises is absent, and the edge was still recorded" "the :stop event itself carries no argument, result or header bytes" "dispatch_opts never enter: a secret handed to every dispatch is in no row, byte or summary" "request headers carrying the marker reach neither the events nor the rows" "a throw and an exit from the dispatch are exceptions of their kind, with marker-free frames; a crafted error_info is dropped from the frames"; `test/beam_mcp/connectome/tracer_test.exs` "a registered name is identity: a secret in a name is published in the bytes, the message beside it is not"; `test/beam_mcp/connectome/diff_test.exs` "an observed graph the collector built from a call carrying a marker diffs to bytes with no marker"; `test/beam_mcp/readme_claims_test.exs` "the observed graph carries edge identity only, never a payload byte" |
| 6 | **claim an MCP capability the specification does not define.** No topology or reachability capability on the wire; `connectome://` is the package's own URI scheme, not a claimed capability. | Capabilities are negotiated with clients that read the specification, not this README. An invented key is a promise no client can act on. The advertised keys are held to `ServerCapabilities` as each revision's schema defines it — a copy of the two key sets taken from the schema files on 2026-09-15 and cited in the test (`tasks` in 2025-11-25; `extensions` in 2026-07-28). The entry bars keys the specification does not define, at the top level and under each capability (`resources` may carry `subscribe` and `listChanged`, nothing else); a key it does define and this package does not implement is a different question, answered by the README. | `test/beam_mcp/boundary/no_invented_capability_test.exs` "server/discover advertises only keys the 2026-07-28 schema defines" "the initialize result advertises only keys the 2025-11-25 schema defines" "no line under lib/ names a topology or reachability capability on the wire" |
| 7 | **issue or honour a session identifier.** Over HTTP no response carries `Mcp-Session-Id`, a request carrying one gets the same status and body as one that does not (held on four methods, including an unknown one), and no line under `lib/` reads or writes one — the name is barred in every delimiter but the backticks of the transport's own docs, which name it to deny it. | Every request stands alone; the 2026-07-28 transport removed sessions. Refusing unestablished callers on a transport where that matters is the host's job, stated in the README. | `test/beam_mcp/boundary/no_session_test.exs` "no response carries an mcp-session-id header, and a request carrying one is answered as if it did not" "no code line under lib/ reads or writes a session identifier" |
| 8 | **carry OAuth.** No authorization flow, discovery document, token endpoint or bearer handling under `lib/` — the `authorization` header is not even read there; it reaches the host's hook untouched. The transport offers `:authorize` and `:authorize_body` hooks and performs no cryptography. | Verifying is the host's work; making it possible is the transport's. A package that performs no cryptography (entries 2 and 3) cannot honestly offer an OAuth server. | `test/beam_mcp/boundary/no_oauth_no_client_test.exs` "no OAuth under lib/" |
| 9 | **be a client.** No module under `lib/` names itself a client, opens an outbound connection (by OTP's names — `gen_tcp`, `ssl`, `socket`, `gen_udp`, `gen_sctp`, `ssh`, `httpc`, `inets`, `open_port`, `os:cmd`, `Node.spawn`/`connect`/`ping`, `net_kernel`, `net_adm`, `rpc`, `erpc` — and the common clients' — `gun`, `hackney`, `Mint`, `Finch`, `Req`, `HTTPoison`, `Tesla`, `Port.open`, `System.cmd`/`shell`; a `GenServer.call` to a name on another node is outside the list), or sends an `initialize` request; every `initialize` under `lib/` is a clause head that receives one, or the list of methods the modern era removed. | A server that also calls out has two threat models, and a page like this one for each; this package keeps one. | `test/beam_mcp/boundary/no_oauth_no_client_test.exs` "no client under lib/: no client module, no outbound connection, initialize only ever received" |
| 10 | **enumerate all paths or match motifs in the connectome.** `all_paths` is refused by name, always; it is not capped; its one definition under `lib/` is the refusal, and no function under `lib/` carries *motif*, *isomorph* or *subgraph* in its name or ends in *paths*. | The number of paths is exponential in the graph; a cap would be a promise to answer "some of them", which is worse than no answer. Motif matching is refused for the same reason. The reachability questions the package does answer are on the reach page. | `test/beam_mcp/connectome/reach_test.exs` "all-paths enumeration is refused by name, not attempted"; `test/beam_mcp/boundary/no_path_enumeration_test.exs` "the only definition of all_paths under lib/ is the refusal, and no motif matcher is defined" |
| 11 | **hold a tool, a domain, or a concrete catalog.** No module under `lib/` implements `BeamMCP.Catalog` — by `@behaviour`, or by defining or delegating `capabilities/0`, which is all the package asks of a catalog — and nothing under `lib/` builds a `%BeamMCP.ToolSpec{}`: the census reads the syntax tree, where a literal in any field order or across any lines, a `%{__struct__: …}` map, a `Map.put` of `__struct__`, a `__struct__/1` call, a `struct/2` or `struct!/2` call, and `%__MODULE__{}` inside the struct's own module are constructions, and a clause-head pattern, the left of a match and `match?/2` are matches. The struct is defined there, matched there, and never constructed there. The catalog is reached through one callee, `capabilities/0`, at three sites, counted — and every call through a variable module under `lib/` is one of those three. The catalog and the dispatch are injected by the host. | The README's opening sentence: the package holds no tools, no domain, and no policy — a commodity protocol layer with nothing of its own to protect or to sell. | `test/beam_mcp/boundary/no_catalog_test.exs` "no module under lib/ implements BeamMCP.Catalog" "no line under lib/ constructs a tool" "the catalog is called through one callee, capabilities/0, at three sites" |

## What a census does not prove

Every entry above is proven by a test over this tree; none rests on reading alone. But a census
reads text, and text has edges worth stating:

- The censuses bar the acts by their written names (`:crypto.sign`, `:public_key.`, `:httpc.`,
  `Mcp-Session-Id`, and so on), whatever delimiter the name is written in (entry 7 allows one:
  backticks, prose). An act under a name the patterns do not list — in this package's own code
  or in a library — would not be seen.
  For key material, which has no name of its own, the patterns bar the ways it would arrive: an
  environment read, a `_KEY` constant, a decoder, a generator. The libraries this package can
  reach are the ones in `mix.lock` (the development tools included) — `jason` and `telemetry`,
  the optional `plug` and `bandit`, and what they bring, which includes `plug_crypto`, a signing
  and key-derivation library; it is barred by name in entries 2 and 3. Nothing in this repository audits what a dependency does;
  the lock file is the list, and a reader who wants the guarantee reads it.
- A name assembled at runtime would defeat every census above. The acts that assemble one —
  `apply/3`, `Module.concat`, code evaluated from a string, an atom made from a binary — are
  barred by their own names (the reader paragraph). The one that has no name of its own — a
  barred word spelled as two strings joined, `"mcp-" <> "session-id"` — is outside every census
  on this page and is not pinned; a reviewer reads for it. Two things under `lib/` are called
  without a written name by design and are the host's code: its catalog module
  (`capabilities/0`, one callee, three sites, counted, and the only calls through a variable
  module under `lib/`) and the functions it hands in as options (the dispatch, the `:authorize`
  hooks).
- A digest is not a signature until a key goes into it. Entry 2's census bars every keyed
  primitive by name, but `:crypto.hash/2` over bytes that happen to contain a secret is a
  construction no census can tell from a hash; the two sites are over canonical bytes, and a
  third would have to say what it hashes.
- Entry 7's wire half is asserted over the HTTP transport, the only transport with headers, on
  requests the transport serves; a session carried under some other header name would be a
  session identifier by another name, which the source half sees only if the name says so.
  Over stdio there is no header to carry one; the source half covers both transports.
- Entry 9's "sends no `initialize`" is a statement about this package's source. A host that wraps
  it and sends one is a client of something else, and out of this page's reach.

## Related

- The README's *Deliberately out* paragraph, which points here.
- The connectome pages: the [vocabulary](connectome.md) defines the graph, its nodes, edges and
  the sign; the [canonical page](connectome-canonical.md) defines the bytes a signer would sign;
  the [diff page](connectome-diff.md) defines the four classes, *dead authority* among them; the
  [reach page](connectome-reach.md) states which questions the package answers and that
  `all_paths` is refused; the [observed page](connectome-observed.md) states the tracer's threat
  model and the payload rule.
