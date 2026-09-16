<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# The threat model

What this package defends, against whom, and by which test — for the whole package. It
extends the model the tracer shipped with in 0.4.0 (`docs/connectome-observed.md`, "The threat
model, which is the boundary of every claim in this section"; the `BeamMCP.Connectome.Tracer`
moduledoc) rather than replacing it: that paragraph's line — accident and failure on a node
running only host-installed code in scope, an adversary executing code inside the same node
out — is the line here too, drawn once for every module. What this page adds is the wire: a
client this package has never met, sending bytes it did not write, and what is refused, what
is bounded, and what is handed to the HTTP server or the host by decision.

**An MCP server library owes the wire, not the model.** What a tool's result does to a
language model that reads it — prompt injection through tool results or resource contents,
OWASP LLM01:2025 — is the host's: this package carries the host's bytes to the client
verbatim and never interprets them, so it can neither inject nor filter. Everything below is
about the bytes on the way in.

Every row of the wire table names the test that enforces it, by path and by name, and a
census holds each citation to the tree
(`test/beam_mcp/threat_model_test.exs` "every test the page cites exists, by path and by name") — the discipline `docs/will-not-implement.md` is held
by. Every number is a measurement, with its date; a number that moves is re-measured, not
edited.

## Who is trusted for what

| party | trusted for | not trusted for |
|---|---|---|
| **the host** — the application that embeds this package | everything: the catalog and the dispatch function it supplies, its `authorize/1` and `authorize_body/2` hooks, the HTTP server and its settings, what it does with a tool's result, the node it runs on | nothing is checked against the host; a host fault is answered as a host fault (`500`, `-32603`) and told to nobody else |
| **the client** on the wire — stdio or HTTP | nothing | every byte: read under a bound, decoded under a bound, matched to the headers it sent, validated against the schema the host declared, refused by name when any of that fails |
| **the node** — every process in the same BEAM | everything, because the BEAM has no in-node isolation | out of scope by physics: see below |
| **this package** | to hold no tool, no key, no signature, no session, no authority, no client, no state between requests, and to claim no capability the specification does not define — each a census under `test/beam_mcp/boundary/`, listed on `docs/will-not-implement.md` | to be a security boundary against the node it runs in |
| **a federation peer** — another node's graph, when the seam exists | not yet defined: the seam is unbuilt (see "Federation") | until the seam states it: everything |

## The wire, vector by vector

Each vector is one of three things: **REFUSED** — this package answers by name and the
request goes no further; **BOUNDED** — this package caps what a request can cost it and
says the cap; **DELEGATED** — the HTTP server or the host holds the line, and this page says
which setting. Measurements are from one 32-scheduler machine, OTP 28, on the dates given. The
OWASP column names the entry each vector answers to: `ASInn` from the *OWASP Top 10 for Agentic
Applications for 2026* (published 2025-12-09), `LLMnn:2025` from the 2025 LLM Top 10 — a
reading of each entry's title, not a claim of coverage.

| vector | this package | what happens, measured | enforced by | OWASP |
|---|---|---|---|---|
| **Oversized body** | BOUNDED, then REFUSED | Each transport caps one body at 1 MiB — exactly 1,048,576 bytes admitted, the byte past it refused, on the HTTP body, the stdio line and the legacy `Content-Length` frame alike (the stdio line counts a trailing `\r` before trimming it, so a CRLF client has one byte less of payload; MCP's framing is LF). Over HTTP the server reads exactly the cap — 1,048,576 bytes, constant across six socket-buffer settings (measured 2026-09-07) — and answers `413` / `-32600` with `connection: close`, so the HTTP server does not drain the rest on behalf of a caller already refused. Over stdio a line past the frame bound is refused as it is read — `-32600` "Request line exceeds 1048576 bytes", the code the HTTP refusal carries, so one vector has one code — the line held as one off-heap binary that the loop retains nothing of (a list of one-byte binaries had cost 46–67 MiB of heap per 1 MiB line, and the legacy `Content-Length` check downcased the whole line for a fifteen-byte prefix, 40 MiB more; 0 MiB sampled at 1 ms during a 1 MiB read now, 2026-09-16), never buffered past the bound, and the rest of the line is drained to its newline so no tail of it is read as the next frame (until this page, the tail was); a legacy `Content-Length` frame declaring more than the cap is refused by name (`-32600` "Request frame exceeds 1048576 bytes") and its declared body drained in chunks, never buffered; every header line of that block is read under the same line bound, and past it the block and its body are drained (a lane sent 64 MiB on one header line and it was read whole) — until this page the body was left on the pipe and a request inside it was dispatched (a lane put one there and watched it answer). | `test/beam_mcp/transport/http_test.exs` "a body over the cap is refused and the connection closed"; `test/beam_mcp/readme_claims_test.exs` "the 1 MiB cap is the number the code enforces" "the server-side read before a refusal is the cap itself, not a range"; `test/beam_mcp/transport/stdio_test.exs` "a line beyond the frame bound is refused rather than buffered"; `test/beam_mcp/threat_model_test.exs` "a line past the frame bound is refused once, its tail discarded to the newline, and the next line answered" "a line of exactly 1 MiB is admitted, one byte more is refused, and the message says exceeds" "a legacy Content-Length frame over the cap is refused by name and its declared body is drained, never read as the next frames" "a header line of a legacy Content-Length block is bounded like any line, and refused by name past it" "reading a line costs the loop about the line's bytes, not sixty times them" "a size refusal is -32600 on stdio as it is over HTTP, so one vector has one code" | LLM10:2025 Unbounded Consumption |
| **Deeply nested JSON** | BOUNDED, then REFUSED | The size cap bounds how deep a body can nest but not what decoding it costs: before this page, a 1 MiB body nested 524,288 levels deep was decoded in full — 79–96 ms and a **38 MiB heap** for one request, ~36× the body — and refused afterwards by its shape (measured 2026-09-16). Now `BeamMCP.JSON.decode/1` walks the bytes once before the decoder runs and refuses a body nesting past **64 levels** with `-32600` "Request body nests deeper than 64 levels" — `400` over HTTP with the connection kept (the body was read in full), the same error object on stdio — having built nothing: the worst body under the cap is refused in microseconds, and the handling process's heap never holds the nest. What the whole bounded decode costs against the decoder alone, by shape (medians of five, 2026-09-16): a 218-byte request 2 µs → 4 µs; a 1 MiB body that is one string 2.0 ms → 4.0 ms; a 600 KB array of digits 19 ms → 42 ms; an 878 KB object of 60,000 keys 21 ms → 45 ms; a 638 KB object nested four deep 17 ms → 44 ms — the key-dense shapes pay most, for the repeated-key check below; the worst nest 58 ms → refused in microseconds; the transient heap of a bounded decode is not above the decoder's own: on the 60,000-key object the sampled peaks (1 ms, medians of five, two lanes, 2026-09-16) are 10.7 MiB bounded against 11.5 MiB for `Jason.decode/1` alone — the time is the cost, not the memory (what a process holds after either returns depends on when it last collected, and is not stated). Sizes given in KB are decimal; MiB is binary throughout. Both transports read through the one function. The number is a constant, for the reason the body cap is one, and it is pinned by bytes — 64 admitted, 65 refused, as literals — and not by the constant it pins. | `test/beam_mcp/threat_model_test.exs` "over HTTP a body nested past the bound is refused by name, -32600 and 400, with the connection kept" "over HTTP a body nested exactly to the bound is not refused for its depth" "the worst body under the size cap is refused with a heap that never held the nest" "over stdio a line nested past the bound is refused by name, and the loop keeps going" "the bound is one number, read from one place, and it is the number the page states" "the number is sixty-four, pinned by bytes and not by the constant it pins" | LLM10:2025 |
| **A repeated key in the body** | REFUSED | Jason keeps the first of two equal keys; most other parsers keep the last. A hop in front of this server that routes on the last `"name"` while this server executes the first is two sources of truth inside one body — the disagreement the header–body match closes, reopened. Now a body that repeats a key in any object, at any depth, is `-32600` "Request body repeats a key: duplicate key \"name\"" (`400` over HTTP, the same object on stdio). The repeat is found in the decoded objects, not the bytes, so `"a"` and `"\u0061"` are one key as every decoder reads them; that is the cost in the row above. | `test/beam_mcp/threat_model_test.exs` "over HTTP a body with a repeated key is -32600 and 400, naming the key" "over stdio a line with a repeated key is -32600 naming the key, and the loop keeps going" "the decoder names the first repeated key at any depth, and admits equal keys in different objects" | ASI02 Tool Misuse (the wire half) |
| **Malformed JSON, a non-object, an empty body** | REFUSED | `-32700` for bytes that are not JSON or an empty body; `-32600` naming the type for JSON that is not an object — on both transports (until this page, stdio answered a string, a number or `null` with silence, and its parse error carried the decoder's inspected struct with the client's own bytes in it; now every refusal names its cause and carries no data); `400` over HTTP. The decoder is `Jason`, called on the bytes the client sent — a hook that verifies a signature over the body sees the client's bytes, since the transport reads them before anything decodes them. | `test/beam_mcp/transport/http_test.exs` "an empty body is a parse error, not an exception" "invalid JSON is a parse error"; `test/beam_mcp/transport/stdio_test.exs` "malformed JSON gets a parse error, and the loop keeps going"; `test/beam_mcp/threat_model_test.exs` "a line that is JSON but not an object is -32600 naming the type, never silence" "a parse error carries no inspected term and none of the client's bytes" | — |
| **Header injection; header–body disagreement** (the MCP-layer smuggling class) | REFUSED | Over HTTP every request carries `MCP-Protocol-Version`, `Mcp-Method`, and for the three methods that name a target `Mcp-Name`, plus any `Mcp-Param-{Name}` a tool's schema declares through `x-mcp-header`; each is held to the body and a disagreement, a missing header, or a second disagreeing value is `-32020` / `400`. A schema may annotate only primitive-typed properties; a tool whose schema annotates an object or a non-primitive is a host fault — every call on it is `500` / `-32603` until the schema is corrected, and the host's log names the header — while a caller's header that disagrees with the body is `-32020` naming the schema's header, never the caller's string. A request's `_meta` is read at `params._meta` only; the top level is refused with `-32602` naming the place, not accepted as a fallback. | `test/beam_mcp/transport/http_test.exs` "a header disagreeing with the body's _meta is a HeaderMismatch" "the header is matched to params._meta: a disagreement is -32020 with 400" "Mcp-Param-{Name} — a second, disagreeing value is not ignored" "a header the schema requires and the client omits is refused" "a refusal names the schema's header, never the caller's string" "an annotated `object` property is the same fault" "the refusal covers every header the transport reads, not just the version header" | ASI02 Tool Misuse (the wire half) |
| **Request smuggling at the HTTP layer** (`Content-Length` / `Transfer-Encoding` disagreement, pipelining) | DELEGATED | The HTTP server frames requests; this Plug reads one framed body through `Plug.Conn.read_body/2` and nothing else. What it adds: a refusal issued before the body is read closes the connection, so a refused caller's body is never read as the next request. The framing itself is `Bandit`'s (or the host's server's). | `test/beam_mcp/transport/http_test.exs` "a body over the cap is refused and the connection closed" | — |
| **DNS rebinding through `Origin`** | REFUSED | `allowed_origins:` is required at `init/1` — there is no default — and a disallowed or second disagreeing `Origin` is `403`, issued before the body is read. Binding the listener to localhost, which the specification says a local server SHOULD, is the HTTP server's option and the host's. | `test/beam_mcp/transport/http_test.exs` "init/1 raises without :allowed_origins" "a disallowed Origin gets 403" "Origin — a second, disallowed Origin is not ignored" | ASI03 Identity & Privilege Abuse |
| **Slow clients; drip bodies** | BOUNDED | `read_timeout:` on `BeamMCP.Transport.HTTP` is the whole-body deadline passed to `read_body/2`: a client that has sent its headers and then drips the body is answered `408` when it lapses, however many bytes arrived — measured through a real `Bandit` listener at 300, 301, 327 ms for a 300 ms deadline and 1,500, 1,500, 1,501 ms for 1,500 ms (2026-09-16). The default is 15,000 ms, a chosen number with its reasoning beside the constant: long enough for a legitimate 1 MiB body on any link measured, short enough that a drip attack costs the host at most the body cap per connection for fifteen seconds (a legitimate request served in under 0.01 s with 12,000 in flight, 2026-09-07). It is a DoS control and the host's: longer behind a slow link, shorter facing the open internet. For two releases this package passed none and the value in force was `Bandit`'s default for such a call — not a server option, and not a choice. | `test/beam_mcp/transport/http_bandit_test.exs` "a drip client is answered 408 at the deadline set, at two values" "init/1 takes read_timeout: and refuses a value that is not a positive integer" "the default is the stated one, and a drip client under it is not answered inside a second" | LLM10:2025 |
| **Connection floods; too many in flight** | DELEGATED | Each in-flight request at the body cap costs about 1.05 MiB, linear to 8,000 concurrent with no plateau (measured 2026-09-07); the ceiling on how many is `num_acceptors × num_connections` of the server (100 × 16,384 under `Bandit`'s defaults), the host's capacity decision. The nesting bound above is what keeps that per-request figure at the body's size rather than thirty-six times it. | — (a server setting) | LLM10:2025 |
| **Header count and size; TLS** | DELEGATED | Both the HTTP server's. This Plug speaks plaintext to the server that terminates TLS for it; a deployment that needs TLS configures it there. | — | — |
| **Unsafe deserialization; code from input** | REFUSED by construction | Input is decoded by `Jason` to strings, numbers, lists and maps and nothing else: no `binary_to_term`, no evaluator, no module or function built from a name in the input, no atom created from a caller's key — 10,000 distinct keys through `tools/call` and `prompts/get` leave the atom table where it was. The `:xref` census over the built beams pins every module the package calls and, on the modules through which code, secrets, the OS or another node could be reached, every function. | `test/beam_mcp/argument_interning_test.exs` "10,000 distinct caller keys through prompts/get and tools/call leave the atom table where it was"; `test/beam_mcp/boundary/no_dynamic_evaluation_test.exs` "no line under lib/ evaluates code or builds a name at runtime, beyond the argument-key atoms"; `test/beam_mcp/boundary/package_reach_test.exs` "the modules the package calls are exactly the listed ones" "on the modules that could reach code, names, secrets, the OS or another node, the functions called are exactly the listed ones" | ASI05 Unexpected Code Execution |
| **Tool arguments the schema does not admit** | REFUSED | `tools/call` validates arguments against the schema `tools/list` advertised — the same struct, one lookup, so the two cannot disagree — and a missing required property or a forbidden one is refused before dispatch — as a tool error result (`200`, `isError: true`, the text naming the property), which is the shape the specification gives a call the tool could not take, not a JSON-RPC error. What a *valid* call does is the host's tool. | `test/beam_mcp/tool_spec_schema_test.exs` "a call missing a required property the catalog declared is refused" "a call carrying a property the catalog's schema forbids is refused" "tools/list advertises the schema the catalog carries" | ASI02 Tool Misuse (the wire half) |
| **A session or identity to steal or replay** | none exists | No session identifier is issued, honoured or read; each request stands alone; identity is the host's `authorize/1`, and this package holds no key and makes no signature, so there is none to steal from it. | `test/beam_mcp/boundary/no_session_test.exs` "no response carries an mcp-session-id header, and a request carrying one is answered as if it did not"; `test/beam_mcp/boundary/no_key_holding_test.exs` "no line under lib/ names key material or calls a crypto function other than :crypto.hash/2"; `test/beam_mcp/boundary/no_signature_test.exs` "no line under lib/ calls a signing or MAC primitive or defines a sign function" | ASI03 |
| **What a refusal or a fault leaks** | BOUNDED | An error carries structured fields, never an inspected Elixir term; a host's error term goes out as JSON; a host fault (raise, throw, exit in dispatch, a hook, or the catalog) is answered `-32603` with the id and no stacktrace — `500` over HTTP; on stdio the same object and the loop goes on (until this page a fault in the host's dispatch ended the stdio loop with nothing written). The `:telemetry` exception event and the transport's log carry a stacktrace of **arities**, never arguments. | `test/beam_mcp/error_payload_test.exs` "a validation failure carries structured fields, not an inspected map" "the human-readable content carries no Elixir syntax either"; `test/beam_mcp/transport/http_test.exs` "throw and exit are answered, not left as an empty 500" "a host authorize/1 that raises, throws or exits is answered, not left as a bare 500"; `test/beam_mcp/threat_model_test.exs` "a host dispatch that raises, throws or exits is answered -32603 with the id, and the loop keeps going"; `test/beam_mcp/connectome/observed_test.exs` "the :exception stacktrace carries arities, never arguments: a function_clause or a BIF error would have put the call's arguments in its top frame" | LLM02:2025 Sensitive Information Disclosure |
| **A payload byte in the observed graph** | REFUSED by construction | The observed graph carries edge identity only — caller, callee, kind, a count — never an argument, a result or a message term; the tracer traces with the `:arity` flag and never reads a message. | `test/beam_mcp/readme_claims_test.exs` "the observed graph carries edge identity only, never a payload byte"; `test/beam_mcp/connectome/tracer_test.exs` "a traced call is a module-level :invoke edge from the caller's module to the callee's, and nothing of the arguments" | LLM02:2025 |
| **The tracer's own cost** (an opt-in, off by default) | BOUNDED | `max_messages` and `max_duration_ms` are required and finite; the count clears every pattern at the limit; a companion process enforces the deadline from outside the tracer's mailbox. The mailbox bound between a call storm and the clear is physics and is stated with its numbers on `docs/connectome-observed.md`. | `test/beam_mcp/connectome/tracer_test.exs` "a limit is required to be positive and finite; there is no unbounded mode" "at max_messages: the count is reached, tracing is off, every pattern is cleared, nothing left behind" "the duration limit stops tracing on time even when the tracer is not being scheduled, and the tracer leaves on the next message rather than draining the queue" | LLM10:2025 |
| **A multi-round-trip request carrying server state back** | none exists | Every request is answered completely or refused; `inputResponses` and `requestState` are read nowhere, so there is no server state for a client to forge. | `test/beam_mcp/boundary/no_mrtr_test.exs` "no line under lib/ reads inputResponses or requestState, and none names InputRequiredResult" | ASI06 Memory & Context Poisoning |
| **A capability, a client, an OAuth flow that is not there** | none exists | No capability the specification does not define is advertised; no module is a client; no outbound connection is opened; no OAuth. What is not built cannot be exploited, and a census holds each absence. | `test/beam_mcp/boundary/no_invented_capability_test.exs` "server/discover advertises only keys the 2026-07-28 schema defines" "the initialize result advertises only keys the 2025-11-25 schema defines"; `test/beam_mcp/boundary/no_oauth_no_client_test.exs` "no OAuth under lib/" "no client under lib/: no client module, no outbound connection, initialize only ever received" | — (an absence; nothing to map) |
| **The supply chain** | stated, not yet audited | Four dependencies, two optional (`plug` and `bandit` are the HTTP transport's; a stdio-only host carries neither); `plug_crypto` arrives through `plug` and is barred by name from `lib/`. A software bill of materials and a provenance statement are scheduled slices, not shipped; until they are, `mix.lock` is the list. | `test/beam_mcp/boundary/no_key_holding_test.exs` "no line under lib/ names key material or calls a crypto function other than :crypto.hash/2" | LLM03:2025 Supply Chain; ASI04 |

## What is out of scope, and why

**An adversary executing code inside the same BEAM node.** Any process on the node can
`:ets.insert` into a public table, `:persistent_term.put` any key, `Process.register` any free
name, `:erlang.trace` any process, call the host's dispatch function directly, or replace a
module with `:code.load_binary/3`. The BEAM has no in-node isolation, and nothing this package
can do makes it a boundary against that; a reader who takes it for one is in more danger than
one who knows it is not. The shape guards on the tracer's running term are robustness against
the in-scope case — a stale term after a crash — not defence. This is the tracer's paragraph,
package-wide: it holds for the collector's table, the server's persistent terms, and every
module here. A node-level boundary is the host's: separate nodes, or a release that runs no
untrusted code.

**What a tool's result does to a model.** Prompt injection through tool results, resource
contents or prompt messages (LLM01:2025; the agentic frame is ASI01 Agent Goal Hijack) is
carried by this package as the host's bytes and never read. The host that chose to expose the
tool, and the client that chose to feed its result to a model, own that vector between them.

**What a valid tool call does.** A call the schema admits reaches the host's dispatch; what
the tool then does — the effect in the world, the privilege it uses — is the host's, and the
connectome exists to make that inspectable (which effects a catalog can reach, and which paths
cross a gate), not to decide it. The sign an edge carries is a consumer's; this package writes
only `:unset` and never treats any sign as suppression.

**Authority.** The verdict on an edge, the key that would sign a finding, the decision that
acts on one: absent by decision (`docs/will-not-implement.md`, entries 1–4). A threat model for
those lives with the consumer that holds them.

## Federation: the trust domains a merge would cross

The federation seam (a scheduled slice, unbuilt) would merge connectome graphs from several
nodes into one. This package's model today reaches one node. What a merge crosses, stated now
so the seam is designed against it rather than discovered by it:

- **Attribution.** Every edge in a merged graph must carry which node's graph asserted it. A
  declared edge from node A about a module that lives on node B is A's claim, never B's
  declaration, and an observed edge is evidence only on the node that observed it. A merge
  that flattens provenance lets one node speak for another.
- **Identity.** `BeamMCP.Connectome.Node.id/1` is the one site for ids, keyed on the server
  name a host supplies; two nodes naming the same server produce colliding ids that are two
  graphs' claims about one name. The seam decides whether a name is scoped by node before
  any merge.
- **Signs.** A sign is a consumer's statement; two nodes' consumers are two authorities. A
  changed-sign finding across nodes is exactly the "two authorities disagreeing" the diff
  already names, and the merged bytes must say which authority wrote which.
- **Integrity in transit.** This package makes no signature and holds no key; a graph that
  crosses a node boundary is verified, if at all, by the host's signer over the canonical
  bytes, whose hash this package computes and never signs. Which key registry verifies a
  sub-graph is the open question the seam is held on.
- **Trust in the peer.** A peer node is, for the model above, the same as a client on the
  wire: nothing it sends is trusted, everything it sends is bounded and refused by name, and
  its graph is data about *its* claims.

## Where this Plug goes in a host's pipeline

This transport reads its own body, through `Plug.Conn.read_body/2` with `length:` set to the
cap, and needs the client's bytes unread: `authorize_body/2` verifies over them, and the
header–body match reads them. **Mount it ahead of `Plug.Parsers`, or exclude its path from
the parsers**: behind `Plug.Parsers` with `:json` the body has been consumed upstream and every
request is answered `-32700 Parse error: empty body` (measured 2026-09-16). `Plug.Parsers`'s
`:length`, `:read_length` and `:read_timeout` therefore govern the host's other routes, not
this one; the cap on this route is the package's, and the read timeout is the server's.

## What this page does not prove

- **The node.** Nothing above holds against code on the same node; see out of scope.
- **The server's settings.** Every DELEGATED row names a `Bandit` default because that is
  the server the measurements were taken under; a host on another server, or with other
  settings, has other numbers, and this package cannot read them.
- **The host's hooks.** `authorize/1` and `authorize_body/2` are the host's; a hook that
  admits everyone admits everyone. Their faults are answered, not their decisions.
- **The 2026 OWASP LLM edition.** The LLM ids above are the 2025 edition's (`LLM01:2025` …),
  read from the project's page on 2026-09-16; a 2026 edition was published 2026-08-03 and its
  numbering was not read for this page. The agentic ids are the *OWASP Top 10 for Agentic
  Applications for 2026* (published 2025-12-09), read the same day from its announcement.
- **What a census does not prove** is stated on `docs/will-not-implement.md` and holds
  here: a barred act under a name no pattern lists, compile-time code, a dependency's own body.
  The citation census asks ExUnit which cited tests are live — the module's own test list
  and tags, where every spelling of `@tag`, `@describetag` and `@moduletag` ends up, and where
  a commented-out test or a `test "…"` inside a string is not — rather than reading the text;
  an `--exclude` at the runner (the suite excludes `:hot_reload` under coverage) it does not see.

## Related

`docs/will-not-implement.md` — what the package will never do, entry by entry, with the test.
`docs/connectome-observed.md` — the tracer's model this one extends, with its measured bounds.
The README's "Resources this Plug bounds, and the ones it does not" — the body cap's three
non-properties, measured.
