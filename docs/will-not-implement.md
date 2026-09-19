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
every decision about them — for entries 1, 4, 7, 11 and 12; a *signer* — a module behind the
one callback `BeamMCP.Signer` names, the reference one in the separate package `beam_mcp_signer` —
for entries 2 and 3; a
client, a logger, an authorization server or a graph-mining library that this project will not
write, for entries 9, 5, 8 and 10; and for entry 6, the specification itself, since only it can
define a capability. Such a request is answered by pointing here, not by widening this package.

The page and the tests are held together mechanically, in both directions, by three tests
(a citation is a path and, on the same line, the names it holds):
`test/beam_mcp/will_not_implement_test.exs` "every test the page cites exists, by path and by name, and every citation names a test" "every test file carrying a boundary marker is cited on the page" "every file under test/beam_mcp/boundary/ carries the marker".
Neither may drift from the other.

## How the censuses read the tree

A **census** is a test over the source rather than over behaviour. The censuses under
`test/beam_mcp/boundary/` — entries 2, 3, 4, 6, 7, 8, 9, 10, 11 and 12 — share one reader
(`test/support/beam_mcp/boundary.ex`): every non-comment line of every `lib/**/*.ex` file, the
same files `mix compile` reads, so an untracked module is seen; doc strings are read too, so a
census that must allow prose says so by pattern. That `lib/**/*.ex` is the whole application is
itself pinned, in the source and in the built artefact — no Erlang sources, no other compile path, Mix's own compilers and no other, no macro, `quote` or compile-time read under `lib/`, and every module the built application lists a `BeamMCP.` one, the `.app` list agreeing with the ebin: `test/beam_mcp/boundary/population_test.exs` "nothing compiles into the application from outside lib/: no Erlang sources, no other elixirc path" "every module the built application lists is a BeamMCP module, and the list is the ebin".
Two older censuses cited below read the tracked files instead (`git`): entry 1's sign census and
the README's word census under entry 4 — a module not yet added to git is outside their count,
which every file in a pull request is inside. Each census was shown red, before it was
committed, by planting its violation under `lib/` and restoring. A census reads text, so its
reach is the reach of its pattern; where a pattern allows a shape, the entry says which.

Three censuses read the **artefact** instead of the text (this one, entry 11's, and the
population census's module list), and this one is what the others rest on. `:xref` over the
beams compiled from `lib/` lists every module and every function the package calls, whatever
the call was spelled — an alias, a pipe, a capture, `apply` under any name, a call without
parentheses on a named module, all resolve to the same edge in the compiled form. It is run
with Erlang's *built-in functions* included: `:xref` omits calls to BIFs by default, and some
of the functions that matter most on `:erlang` — `apply/3`, `binary_to_term/1`,
`list_to_atom/1`, `binary_to_atom/2` — are BIFs the default listing does not see (measured;
`spawn/2` and `open_port/2` it does). The lists are
pinned exactly: the modules the package calls (`:xref` itself among them: the declared
connectome reads beams with it); on the modules through which code, names, secrets, the
operating system, the disk, another process or another node could be reached (`:erlang`,
`:code`, `Code`, `System`, `Application`, `:application`, `:trace`, `:crypto`, `:ets`,
`:xref`, `:io_lib`, `:logger`, `Logger`, `:digraph`, `:atomics`, `:telemetry`, `Jason`,
`Process`, `GenServer`, `Supervisor`, `Plug.Conn`, `Plug.Exception`, `IO`), the functions; the
one atom the package makes from a binary, by the function that makes it; and every atom in
the compiled forms that names a module — an `Elixir.`-prefixed atom is a module name by construction, installed here or not; an Erlang-style one, if this VM can load it — whatever it was written for —
a module handed to a supervisor as a child spec's `{m, f, a}`, or to anything else as data,
is named there whether or not it is ever called, so that set is pinned too: the called modules
plus eight that arrive through attributes, export lists, option names, a tuple tag — and one,
`json`, that is a local function name OTP 28 turned into a module's name: the loud collision
this census is built to have (`shell` would trip it the same way). The eight are exact for the
OTP the gate runs; an older OTP without a `json` module reads one fewer. The population is the build's ebin, not Mix's `.app` file, which is
regenerated on a one-second mtime and can miss a module compiled in the same second. A new
library, an evaluator, a socket, a shell, a spawn to another node, a key store, an environment
read, a file read or an atom decoded from the wire fails here until it is named:
`test/beam_mcp/boundary/package_reach_test.exs` "the modules the package calls are exactly the listed ones" "on the modules that could reach code, names, secrets, the OS or another node, the functions called are exactly the listed ones" "the one atom made from a binary is made in Server.declared_atoms/1" "every atom in the compiled forms that names a module is a called module or one of the nine named as data".
What runs at *compile time* — a module body, an attribute's expression — leaves no call in the
beam and is outside every artefact census; the text holds that line instead, by name. **The
census's patterns are the list**; this paragraph names their classes, not their spellings. The
classes: macro and guard definitions, `quote`, `unquote`, `unquote_splicing`; the Elixir and
Erlang evaluators and compilers (`Code` except `Code.ensure_*`, `:elixir`, `:elixir_*`,
`:compile`, `:erl_eval`, `:erl_parse`, `:erl_scan`, `EEx`, `Mix`); the four `:code` loaders
(`load_*`, `atomic_load`, `prepare_loading`, `finish_loading`); the readers of the environment
and the disk (`:os.`, `File.`, `:file.`, `:prim_file.`, `:filelib.`, `Path.wildcard`,
`:init.`, and twelve named readers on `System` and `Application`); a quoted
atom carrying a `\x` or `\u` escape (the two escapes that can spell a letter), any word sigil
at all — one string sigil is allowed by its exact line; every other `~w`, whatever its
delimiter, lines, escapes or modifier, and the macro called by name, is refused — and the
Erlang names above in quotes; an atom built by *interpolation* is the joined-strings edge
below, read by nothing; and every `import`, `alias` or `require` that would bring any of these in under another name,
across lines. Three allowances by exact line: the package's own version read from `mix.exs`,
the tracer's threat model naming the loader it does not call, and the HTTP transport's one
word sigil, which makes strings. Beside the census, the
compiler's `warnings_as_errors` (in `mix.exs`) refuses a needlessly quoted atom outright — a
bar this package's build has and a stranger's might not. A reach under a name not in those
classes, run in a module body, is held by nothing but a reviewer's eye — the reader that
would see a module body by what it does is a compiler tracer, and it is not built. Macros
*invoked* from Elixir and the dependencies — `use GenServer`, `defstruct`, `Logger.error` —
expand under `lib/` as anywhere and are the dependency list's, held by their names only; the
one Elixir macro that reads the disk at expansion, `EEx.function_from_file`, is barred by its
name.

The dependency set is pinned beside it by name, as declared and as locked (a `path:` dependency never reaches the lock; a source or checksum is not read):
`test/beam_mcp/boundary/population_test.exs` "the dependencies mix.exs declares are exactly the listed ones" "the dependencies the lock file holds are exactly the listed ones".
The text census for the same acts stays beside it, for the line it names:
`test/beam_mcp/boundary/no_dynamic_evaluation_test.exs` "no line under lib/ evaluates code or builds a name at runtime, beyond the argument-key atoms".

## The entries

| # | The package will never | Why | Enforced by |
| -- | -- | -- | -- |
| 1 | **compute or populate a sign.** `:allow`, `:deny`, `:hold` and `:ungoverned` are a consumer's; the package writes `:unset` — no sign has been supplied to it — into every edge's sign slot, on both graphs, and treats no sign as suppression. | A sign is a verdict. The package exports topology and lets the verdict be somebody else's, so that nothing in it can be mistaken for approval; and a sign it cannot attribute to a decider is not a reason to leave an edge out of a record. | `test/beam_mcp/connectome/census_test.exs` "no code line under lib/ writes or names a sign other than :unset" "no code line under lib/ filters, hides or downgrades an edge on the basis of its sign"; `test/beam_mcp/readme_claims_test.exs` "the package writes only :unset into the sign slot, on both graphs" |
| 2 | **hold a key.** No line under `lib/` generates, loads, decodes or stores key material. The one cryptographic function the package calls is `:crypto.hash/2`, a digest with no key in it — one site, over canonical bytes, the algorithm a variable bound from the caller's option (SHA-256 by default, SHA-384 or SHA-512 by choice, the envelope naming which) and never a literal, and the count is pinned so that a second site has to say what it hashes. | A package that holds a key can be asked to use it. The canonical bytes exist so that a consumer can sign them without importing this package. | `test/beam_mcp/boundary/no_key_holding_test.exs` "no line under lib/ names key material or calls a crypto function other than :crypto.hash/2" ":crypto.hash/2 is called at one site, over canonical bytes, with the algorithm a variable"; `test/beam_mcp/boundary/package_reach_test.exs` "on the modules that could reach code, names, secrets, the OS or another node, the functions called are exactly the listed ones" |
| 3 | **make a signature of its own.** No signing or MAC primitive is called under `lib/`, and no key is held. The one `sign/2` defined there is `BeamMCP.Signer.None`, a no-op answering `{:error, :no_signer}`; the one call of a signer is `BeamMCP.Connectome.Canonical.signature/3`, which hands the canonical bytes to a host-supplied module implementing `BeamMCP.Signer` — exactly one callback, `sign(canonical_bytes, opts)`, two arguments with those names — and places what comes back beside them. The key and the primitive live in the separate package `beam_mcp_signer`. | Signing bytes publishes nothing about who decides what; a richer callback would, so the census pins the shape and any widening is a visible act. The `sign` field an edge carries is the host's verdict slot (entry 1), a value and not an act. | `test/beam_mcp/boundary/no_signature_test.exs` "no line under lib/ calls a signing or MAC primitive" "exactly one `def sign` under lib/: the no-op, spelled as pinned, in its own file" "the behaviour has exactly one callback, sign/2, with the pinned argument names and return" "exactly one call of a signer under lib/: signature/3's, over encode/2's bytes"; `test/beam_mcp/boundary/package_reach_test.exs` "the modules the package calls are exactly the listed ones" |
| 4 | **decide authority.** It writes no verdict (entry 1: the sign slot is only ever `:unset`) and names no receipt (a signed record that a call happened), no approval (a decision that a call may proceed), no risk tier (a ranking of calls by consequence), no egress and no mask (the withholding or rewriting of what leaves the system) — any word containing *receipt*, *approv*, *egress*, *tier* or *mask* (a "frontier" in prose would trip it, loudly, and be read). | Every one of these is a decision about the host's tools, and the package holds none of them; the moment it held one, its topology could be mistaken for a verdict. The words "verdict" and "authority" are not barred: under `lib/` they name the host's slot in the edge's docs and the diff's own class, *dead authority* — terms the package defines, not acts it performs. The acts are barred in the spellings code uses as well as prose. | `test/beam_mcp/boundary/no_authority_test.exs` "no line under lib/ names a receipt, an approval, a risk tier, egress or a mask, in any spelling"; `test/beam_mcp/connectome/census_test.exs` "no code line under lib/ writes or names a sign other than :unset"; `test/beam_mcp/readme_claims_test.exs` "deliberately out: no line under lib/ names a receipt, an approval, a risk tier or egress" |
| 5 | **put a payload byte into the observed graph.** Edge identity only: never an argument, a result, a header, an error message or a stack frame's contents. | A wiring diagram that carries payloads is a log, and a log of tool calls is the most sensitive artefact a host produces. The observed graph is safe to export because it cannot contain what was said. | `test/beam_mcp/connectome/observed_test.exs` "a marker in a nested argument map and in a uri argument is absent from rows, bytes, sidecar and latency" "a marker in the error a dispatch returns is absent" "a marker in an exception a dispatch raises is absent, and the edge was still recorded" "the :stop event itself carries no argument, result or header bytes" "dispatch_opts never enter: a secret handed to every dispatch is in no row, byte or summary" "request headers carrying the marker reach neither the events nor the rows" "a throw and an exit from the dispatch are exceptions of their kind, with marker-free frames; a crafted error_info is dropped from the frames"; `test/beam_mcp/connectome/tracer_test.exs` "a registered name is identity: a secret in a name is published in the bytes, the message beside it is not"; `test/beam_mcp/connectome/diff_test.exs` "an observed graph the collector built from a call carrying a marker diffs to bytes with no marker"; `test/beam_mcp/readme_claims_test.exs` "the observed graph carries edge identity only, never a payload byte" |
| 6 | **claim an MCP capability the specification does not define.** No topology or reachability capability on the wire; `connectome://` is the package's own URI scheme, not a claimed capability. | Capabilities are negotiated with clients that read the specification, not this README. An invented key is a promise no client can act on. The advertised keys are held to `ServerCapabilities` as each revision's schema defines it — a copy of the two key sets taken from the schema files on 2026-09-15 and cited in the test (`tasks` in 2025-11-25; `extensions` in 2026-07-28). The entry bars keys the specification does not define, at the top level and one level under each capability whose sub-keys the schema names (`tools`: `listChanged` — the only capability advertised today; `resources`, `prompts` and `tasks` are held the day they are advertised; `completions`, `logging`, `experimental` and `extensions` are open objects and nothing is read under them; a third level is not read); a key it does define and this package does not implement is a different question, answered by the README. | `test/beam_mcp/boundary/no_invented_capability_test.exs` "server/discover advertises only keys the 2026-07-28 schema defines" "the initialize result advertises only keys the 2025-11-25 schema defines" "no line under lib/ names a topology or reachability capability on the wire" |
| 7 | **issue or honour a session identifier.** Over HTTP no response carries `Mcp-Session-Id`, a request carrying one gets the same status and body as one that does not (held on four methods, including an unknown one), and no line under `lib/` reads or writes one — the name is barred in every delimiter and casing (`mcp-session-id`, `McpSessionId`, `session_id`), with one allowance: the hyphenated header name written directly after the words "no `" — the transport's own denial. | Every request stands alone; the 2026-07-28 transport removed sessions. Refusing unestablished callers on a transport where that matters is the host's job, stated in the README. | `test/beam_mcp/boundary/no_session_test.exs` "no response carries an mcp-session-id header, and a request carrying one is answered as if it did not" "no code line under lib/ reads or writes a session identifier" |
| 8 | **carry OAuth.** No authorization flow, discovery document, token endpoint or bearer handling under `lib/` — the `authorization` header is not even read there; it reaches the host's hook untouched. The transport offers `:authorize` and `:authorize_body` hooks and performs no cryptography. | Verifying is the host's work; making it possible is the transport's. A package that performs no cryptography (entries 2 and 3) cannot honestly offer an OAuth server. | `test/beam_mcp/boundary/no_oauth_no_client_test.exs` "no OAuth under lib/" |
| 9 | **be a client.** No module under `lib/` names itself a client, opens an outbound connection, or sends an `initialize` request. The artefact holds the outbound half whatever the spelling: none of `gen_tcp`, `ssl`, `socket`, `gen_udp`, `ssh`, `httpc`, `inets`, `os`, `peer`, `net_kernel`, `rpc`, `Port`, `File` or any HTTP client is among the modules the package calls, and of `:erlang` only `spawn/1` — the local one — is; the text census names the same by word. A message to a process registered on another node (`send/2`, `GenServer.call/2` to a `{name, node}`) is the one outbound act the compiled form cannot tell from a local one; every `initialize` under `lib/` is a clause head that receives one, or the list of methods the modern era removed. | A server that also calls out has two threat models, and a page like this one for each; this package keeps one. | `test/beam_mcp/boundary/no_oauth_no_client_test.exs` "no client under lib/: no client module, no outbound connection, initialize only ever received"; `test/beam_mcp/boundary/package_reach_test.exs` "the modules the package calls are exactly the listed ones" |
| 10 | **enumerate all paths or match motifs in the connectome.** `all_paths` is refused by name, always; it is not capped; its one definition under `lib/` is the refusal, and no function under `lib/` carries *motif*, *isomorph*, *subgraph*, *path* or *walk* in its name — except the bare names `path` and `walk` — reach's own witness builder and dominator pass — allowed by name alone, in any module and at any arity. | The number of paths is exponential in the graph; a cap would be a promise to answer "some of them", which is worse than no answer. Motif matching is refused for the same reason. The reachability questions the package does answer are on the reach page. | `test/beam_mcp/connectome/reach_test.exs` "all-paths enumeration is refused by name, not attempted"; `test/beam_mcp/boundary/no_path_enumeration_test.exs` "the only definition of all_paths under lib/ is the refusal, and no motif matcher is defined" |
| 11 | **hold a tool, a domain, or a concrete catalog.** No module under `lib/` implements `BeamMCP.Catalog` — by `@behaviour`, or by defining or delegating `capabilities/0`, which is all the package asks of a catalog — and nothing under `lib/` builds a `%BeamMCP.ToolSpec{}`, in any spelling: in the compiled form of every module under `lib/`, the atom `BeamMCP.ToolSpec` occurs only inside a map *pattern* — a literal, an alias, a `struct/2`, a `Map.put` of `__struct__`, a map update of `__struct__`, a map *key*, a `%__MODULE__{}` in its own module or a variable bound to the module all leave the atom somewhere else, and the compiler-generated sites are not skipped but pinned — the struct's own `__struct__/0,1` and Catalog's callback info, exactly, so an `unquote` of a hand-built syntax tree marked generated is one site too many. What this does not see is a tool derived from a tool the package was handed — a matched struct updated field by field carries no atom of its own; nothing under `lib/` does that today, and it is a reviewer's line. The struct is defined there, matched there, and never constructed there. The catalog is reached through three callees, `capabilities/0` at five sites, `read_resource/1` at one and `get_prompt/2` at one — in the compiled form every call through a module known only at runtime, with parentheses, is one of those seven; the one read is reached only after the catalog's own `capabilities/0` has listed the uri or a template that matches it, and the one render only after it has listed the prompt and the tools validator has passed the arguments (a call through a function *value* is a closure, the host's dispatch and hooks or the package's own, and not a module call); and the one spelling the compiled form cannot tell from a field access — `m.capabilities` without parentheses, a deprecated form — is held by the list of every name the package reaches by dot syntax, pinned exactly — its own fields, `conn.method`, and a rescued exception's `__struct__` (names, not module–name pairs: a runtime module whose export shares a field's name, `m.nodes` with `m = :erlang`, is inside the list). The catalog and the dispatch are injected by the host. | The README's opening sentence: the package holds no tools, no domain, and no policy — a commodity protocol layer with nothing of its own to protect or to sell. | `test/beam_mcp/boundary/no_catalog_test.exs` "no module under lib/ implements BeamMCP.Catalog" "no line under lib/ constructs a tool" "the catalog is called through three callees: capabilities/0 at five sites, read_resource/1 at one, get_prompt/2 at one" "every name the package reaches by dot syntax is on its pinned list" |
| 12 | **run a multi-round-trip request.** The `2026-07-28` revision lets a server answer `tools/call`, `resources/read` or `prompts/get` with an `InputRequiredResult` and finish on a later request carrying `inputResponses` and a `requestState` of the server's own. This package answers every request completely or refuses it: the one `resultType` written under `lib/` is `"complete"`, at one site, and neither continuation parameter is read anywhere — a request carrying them is served as if it carried neither, since nothing here ever asked for input. | An input-required round trip is a conversation with state between two messages — what was asked, what came back, what the server had decided so far — and this core has no process and no state of its own by design: one message in, one response out. The `requestState` the revision offers as the server's opaque continuation would carry the server's own decision state for a client to hand back — unlike the pagination cursor, which names a position any client may name by other means and carries no decision. A host that wants the round trip owns exactly the state it needs to run it, above this core. Named by the owner as the one item of the `2026-07-28` surface nobody had placed; placed here, out, so nobody later improves it in by accident. | `test/beam_mcp/boundary/no_mrtr_test.exs` "the only resultType written under lib/ is complete, at one site" "no line under lib/ reads inputResponses or requestState, and none names InputRequiredResult"; `test/beam_mcp/mrtr_wire_test.exs` "on the core, at both eras, the answer with the continuation parameters is the bare answer" "through the HTTP transport the answer with the continuation parameters is the bare answer" |

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
- A name assembled at runtime would defeat every text census above. The acts that assemble one
  — `apply`, `Module.concat`, an evaluator, a loader, an atom made from a binary — are calls,
  and the artefact census sees every *runtime* call by its compiled target, so those are held
  whatever they are spelled; what runs at compile time is held by the text (the reader
  paragraph). What has no call in it — a barred *word* spelled as two strings joined,
  `"mcp-" <> "session-id"`, a header name that is data and not code — is outside every census on
  this page and is not pinned; a reviewer reads for it, as for the compile-time reach above:
  those two are what a reviewer's eye holds here. The text reader drops a line beginning `#`
  as a comment unless it carries a `#{` — an interpolation inside a string is code and is read.
  Two things under
  `lib/` are called without a written name by design and are the host's code: its catalog module
  (`capabilities/0` at five sites, `read_resource/1` at one and `get_prompt/2` at one: three
  callees, and the only named calls through a runtime module)
  and the functions it hands in as options (the dispatch, the `:authorize` hooks).
- A digest is not a signature until a key goes into it. Entry 2's census bars every keyed
  primitive by name, but `:crypto.hash/2` over bytes that happen to contain a secret is a
  construction no census can tell from a hash; the one site is over canonical bytes, and a
  second would have to say what it hashes.
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
