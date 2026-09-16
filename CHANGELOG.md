<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed — the canonical envelope names its algorithm; `schema_version` 3; SHA-384 and SHA-512 by option

- **The algorithm is in the bytes.** A canonical envelope carries a fourth top-level member,
  `"algorithm"`, right after `"schema_version"`: `"sha256"`, `"sha384"` or `"sha512"`, and its
  hash is that digest over exactly those bytes, so a verifier reads the algorithm from what it
  holds (`docs/connectome-canonical.md`, rules 1 and 9, with the worked example under all three;
  `docs/connectome.md` defines the three names). The diff record gains the same member (its
  keys sort, so it comes first; `docs/connectome-diff.md`). **`schema_version` is `3`** on the
  graph and on the diff record, and `BeamMCP.Connectome.Graph.new/1` refuses `2` as it refused
  `1` — bytes are produced and hashed here, never re-imported. **Breaking for a consumer that
  parses the envelope with a fixed member list**; nothing else about the layout moved.
- **SHA-256 stays the default, indefinitely; the other two are an option, never a constant.**
  `algorithm:` on `BeamMCP.Connectome.Canonical.encode/2`, `hash/2`, `hash_hex/2`,
  `hash_value/2`, on `BeamMCP.Connectome.Diff.encode/2`, `hash/2`, `hash_hex/2`, and in
  `BeamMCP.Connectome.Surface`'s host options; anything outside the three is refused by
  `ArgumentError` naming it, before a byte is written. The digest is computed at one site under
  `lib/`, with the algorithm a variable — the key-holding census now pins one site, not two.
  The wire's `tools/call` result keys the hex by the algorithm's name: `sha256` as before under
  the default, `sha384` or `sha512` when the host chose one.
- **A verifier holding 0.4.0 or 0.5.0 bytes** (`schema_version` 1 or 2) hashes them, unchanged,
  with SHA-256 and compares — those bytes name no algorithm, and at those versions the digest is
  SHA-256 by the page's rule; published hashes stay verifiable forever. The canonical page's
  *Versions* section says so in full, and 0.5.0's goldens are kept in the tree and verified that
  way by a test.
- **Two pages:** `docs/crypto-posture.md` (one primitive at one site; three digests named in the
  bytes; no key, no signature; the seam for a signing package) and `docs/fips.md` (what a
  FIPS-mode host needs — a `crypto` built against a validated OpenSSL FIPS provider,
  `application:start(crypto)`, `enable_fips_mode/1` or `fips_mode: true` — and that this
  package enables none of it and cannot, by census).
- **Fixed on the way: the `.app` now requires `crypto`.** It did not; an HTTP host had it only
  through `plug` and `bandit`, both optional, and a stdio-only release built from the `.app`
  would have had no `:crypto.hash/2` at all. Found by writing the FIPS page's sentence about it
  and reading the built `.app`; pinned by a test that reads the `.app`.
- **How to tell whether you are affected:** a consumer that verifies by hashing the bytes it
  holds is not — the member is under the hash like every other. A consumer that parses the
  envelope by position or by a fixed member list meets `"algorithm"` at the second position.
  A host that passes nothing gets `sha256` everywhere it did. Latency stays out of the signed
  envelope, by decision: it is a measurement of one machine on one day, not a property of the
  graph, and lives in the unsigned sidecar as before.

### Added — the HTTP body read deadline is the Plug's option, and its default is a chosen number

- **`read_timeout:` on `BeamMCP.Transport.HTTP`** — one whole-body deadline, this package's
  own. The body is read in pieces against one monotonic clock, each read given what remains, so
  a client that has sent its headers and then drips the body is answered `408` when it lapses,
  however many bytes arrived and however the adapter splits the reads. Measured through a real
  `Bandit` listener: `408` at 300, 301, 327 ms for a 300 ms deadline and 1,500, 1,500, 1,501 ms
  for 1,500 ms. The default is 15,000 ms — the number the transport has been running under —
  but chosen now, with its reasoning beside the constant: for two releases this package passed
  no `:read_timeout` and the value in force was `Bandit`'s default for such a call, which the
  README called "inherited from the server"; a review lane read `Bandit` and `ThousandIsland`
  and found no server option for the body read, so nobody had chosen it and no host could
  change it. And the adapter's `:read_timeout` is a per-read clock, not a whole-body one —
  three ways, each measured by a lane and each closed: a cap-sized body is two reads and got
  two deadlines (1,909 ms for 1,000); a chunked body is read chunk by chunk, each on its own
  clock, and a client sending one byte per chunk was served after 43 s under the 15 s default —
  so **`transfer-encoding: chunked` is refused with `411` before the body is read** (an MCP
  request is one complete JSON message under a 1 MiB cap; no MCP client this package has been
  run against sends one); and over HTTP/2, which `Bandit` serves on the same listener, the
  reader gathers DATA frames on a per-frame clock and a one-byte-per-frame drip of a valid call
  was served after 20 s under a 300 ms deadline — now the reader is asked for less than one
  frame, so every DATA frame, an empty one included, returns to the deadline's clock (a stream
  kept open by control frames alone is held by the adapter's own wait past the deadline; the
  threat model states it, with the cost). Over HTTP/2 every refusal issued before
  the body is read had carried `connection: close`, a malformed response there (RFC 9113), and
  an HTTP/2 client saw a stream reset in place of the `403`, `405`, `413`; the header is
  HTTP/1.1's now and the refusal arrives. A value that is not a positive integer is refused at
  `init/1` by name. The threat model's slow-client row moves from delegated to bounded, with
  the tests, and a row for the undeclared length joins it. **How to tell whether you are
  affected:** a host that passes nothing sees the same 15 s it always had, now enforced as one
  deadline. Two things change on the wire and in the log: the `408` was `Bandit`'s bare status
  line with no body and is now this package's JSON-RPC refusal (`-32600`, the deadline named)
  with `connection: close` over HTTP/1.1; and the adapter's error-level log line at its read
  timeout (`Bandit.HTTPError Read timeout`) no longer fires, because the deadline is no longer
  the adapter's — a host alerting on that line loses the signal, and nothing is written for a
  `408` or a `411`. A client whose author sent a chunked body gets `411` until it sends a
  `Content-Length`.

### Added — the threat model, package-wide, with the wire bounded vector by vector

- **`docs/threat-model.md`**: who is trusted for what — the host for everything, the client on
  the wire for nothing, the node for everything by physics, this package for holding no tool,
  key, signature, session, authority or client — and the wire vector by vector, each
  **refused**, **bounded** or **delegated** to the HTTP server or the host by decision, with the
  test that enforces it by path and by name and the OWASP entry it answers to (the *OWASP Top 10
  for Agentic Applications for 2026*, published 2025-12-09; the 2025 LLM Top 10, by edition —
  read from the source). It extends the tracer's threat model shipped in 0.4.0 rather than
  replacing it: an adversary executing code inside the same node stays out of scope, now for
  every module, with the reason; prompt injection through tool results is the host's
  (LLM01:2025) — this package carries bytes and never reads them. A federation section states
  the trust domains a merge would cross — attribution, identity, signs, integrity in transit,
  the peer as a client — so the seam is designed against them. Where the Plug goes in a host's
  pipeline: ahead of `Plug.Parsers`, or its path excluded — behind the parsers every request is
  `-32700 Parse error: empty body` (measured). A census holds every citation on the page to a
  test in the tree, the discipline the will-not-implement page is held by. Two things the page
  corrects in the README on the way: the body read's 15,000 ms is `Bandit`'s default for a
  `read_body/2` call that passes no timeout — which is what this package passes — and not a
  server option a host can set; and the 12,000-in-flight measurement is dated to its record
  (2026-09-07).
- **JSON nesting is bounded before the decoder runs, on both transports.** The 1 MiB body cap
  bounds how deep a body can nest but not what decoding it costs: a 1 MiB body nested 524,288
  levels deep was decoded in full — 79–96 ms and a 38 MiB heap for one request, about 36× the
  body — and refused only afterwards by its shape. `BeamMCP.JSON.decode/1`, now the one place
  the wire's JSON is read, walks the bytes once — brackets outside strings, escapes honoured —
  and refuses a body nesting past **64 levels** with `-32600` "Request body nests deeper than 64
  levels" (`400` over HTTP with the connection kept, since the body was read; the same object on
  stdio), building nothing: the worst body under the cap is refused in microseconds. Sixty-four:
  a request is three levels deep before the host's data begins, and nothing in the conformance
  suite or this package's tests comes near it; the number is a constant, for the reason the body
  cap is, and it is pinned by bytes (64 admitted, 65 refused, as literals) after a review lane
  moved the constant to 8 and the suite stayed green.
- **A repeated key in the body is refused, on both transports.** Jason keeps the first of two
  equal keys; most other parsers keep the last, so a hop in front of this server that routed
  on the last `"name"` while this server executed the first was two sources of truth inside
  one body — the disagreement the header–body match exists to close, reopened (found by a
  review lane driving the wire). Now a body that repeats a key in any object, at any depth, is
  `-32600` "Request body repeats a key: duplicate key \"name\"" (`400` over HTTP). The repeat
  is found in the decoded objects, not the bytes, so `"a"` and `"\u0061"` are one key as every
  decoder reads them. What the bounded decode costs against the decoder alone, by shape: a
  request-sized body 2 µs → 4 µs; a 1 MiB body that is one string 2.0 → 4.0 ms; key-dense
  bodies of 600–900 KB 17–21 → 42–45 ms — the ordered-object decode and a second walk,
  the price of comparing keys after unescaping. **How to tell whether you are affected:** a client
  that nests a body past 64 levels or repeats a key in an object now gets `-32600` naming the
  cause; no field, method or capability moves.

### Fixed — the stdio loop under a hostile line or a host fault

- Four things the threat model's rows claimed transport-wide and a review lane measured false on
  stdio, each red first. **A host fault ended the loop:** a dispatch function, catalog or hook
  that raised, threw or exited took `BeamMCP.Transport.Stdio.run/1` down with nothing written,
  and every request queued behind it was never answered; now it is answered `-32603 Internal
  error` with the request's id, the log line carries arities and never arguments, and the loop
  goes on — as the HTTP transport has always answered `500`. **A line that was JSON but not an
  object got silence** (a string, a number, `null`, `true` were served as notifications); now
  `-32600 Expected a JSON object, got a string` and the like, as over HTTP. **A parse error
  carried `data: inspect(reason)`** — the decoder's struct, with the client's own bytes in it,
  up to `inspect`'s printable limit; now every refusal names its cause in the message and
  carries no data (`-32700 Parse error: body is not valid JSON`; a size refusal `-32600 Request
  line exceeds 1048576 bytes`, the code the HTTP transport's `413` carries, so one vector has
  one code on every transport — it was `-32700` on stdio). **The tail of an over-long line was
  read as the next frames** — refused once at the bound, then the remainder decoded as a fresh
  message and refused again, and a test recorded that as observed; now the rest of the line is
  drained to its newline, byte by byte and never buffered, so the refusal is one line and the
  tail is nobody's frame. **A legacy `Content-Length` frame declaring more than the cap** was
  refused and its body left on the pipe, so a request inside that body was read as the next
  frame and dispatched (a consumer-parse-back lane put a `tools/call` there and watched it
  answer); now the declared body is drained in chunks, never buffered, and the refusal names the
  frame: `-32600 Request frame exceeds 1048576 bytes`. **A header line of that block was read
  with no bound** — a lane sent 64 MiB on one and it was read whole; now every header line is
  read under the line bound, and past it the block and its declared body are drained. **And the
  line itself was held as a list of one-byte binaries** — 46–67 MiB of heap for a 1 MiB line
  (measured); now the line is one off-heap binary and the loop retains none of it — and the
  sampler that pinned it found a second forty: the legacy `Content-Length` check downcased the
  whole line to read a fifteen-byte prefix, 40 MiB of heap per 1 MiB line; now the prefix alone
  (0 MiB sampled). **And the line cap admits exactly 1 MiB:** a line of 1,048,576 bytes was
  refused as exceeding a bound it met, one byte early against the HTTP body and the legacy
  frame; now the byte past the cap is the refusal on all three. A client that sent well-formed
  lines under the cap sees no change.

## [0.5.0] — 2026-09-16

Everything since `0.4.0`, grouped by the change that made it. **What moved on the wire in this
release**, each in its own entry below: three resources methods, two prompts methods and one
pagination cursor added, with the `resources` and `prompts` capabilities they advertise in
`initialize` and `server/discover`; `server/discover`'s result filled to the `2026-07-28`
`DiscoverResult` and a transport's advertised revisions narrowed to what it serves; `Mcp-Name`
required on `resources/read` and `prompts/get` over HTTP; a tuple error reason encoded as an
array and `-32022`'s `data.requested` sent as a string; and one break on the wire — the
request `_meta` read at `params._meta` and refused at the top level. The sign-vocabulary break
is in the exported bytes, not a break on the wire — no 0.4.0 method carried a sign; the
surface that now carries the bytes is new. The two catalog breaks are in the host contract.
**The connectome surface moved nothing:** the five advertising methods were recorded on the
core and through the HTTP transport before `BeamMCP.Connectome.Surface` existed
(`test/fixtures/wire/pre-017.json`), and `test/beam_mcp/wire_recording_test.exs` holds the
same catalog to that recording and the catalog with the surface's entries to the recording
plus exactly those entries, `server/discover` identical. No capability is claimed that the
specification does not define; the census under `test/beam_mcp/boundary/` holds that.

### Added — the connectome on the wire, as the host chooses; multi-round-trip requests named out

- **`BeamMCP.Connectome.Surface`**: three read-only resources — `connectome://declared`,
  `connectome://observed`, `connectome://diff` — for a host to put in its own catalog, and
  `call/2` for the one `:observe` tool a host that exposes tools only writes itself (the package
  holds no tool, by the will-not-implement page's entry 11; the spec to copy is in the
  moduledoc). Each answers the canonical bytes of the graph, **byte-identical to the file
  export** (`BeamMCP.Connectome.Canonical.encode/1`; the diff record
  `BeamMCP.Connectome.Diff.encode/1`), and nothing else; the tool carries the bytes verbatim
  under `bytes` in its structured content with their SHA-256 beside them, so a client verifies
  without re-encoding (its text content is the server's rendering of that map, as for every
  tool). The host's `read_resource/1` and dispatch delegate to `read/2` and `call/2` with
  `declared:` (the builder's options), `observed:` (the collector's name) and `window:` (the
  consumer's map); a missing one is refused by name, a collector not started is `:not_started`,
  a build refusal is the builder's verbatim. Read-only by construction and by test: the
  collector's rows and the package's persistent terms are compared before and after and held
  equal (the tool's own call is a dispatch, which a running collector records like any other).
  **Nothing else on the wire moves:** a recording of `server/discover`, `tools/list`,
  `resources/list`, `resources/templates/list` and `prompts/list`, on the core and through the
  HTTP transport, taken before this change and kept in the tree, is what the same catalog still
  answers, and the catalog with the entries added answers that plus exactly the entries —
  `server/discover` identical as decoded JSON, no capability claimed (`connectome://` is a URI
  scheme, served by the resources primitive). Pagination of a large graph's bytes and
  subscriptions on `connectome://observed` are not here.
- **No Cypher exporter, on purpose.** The canonical bytes load into Neo4j with APOC's JSON
  loader — two statements over `nodes` and `edges`, shown in the Livebook and named on the
  canonical page — and a fourth rendering would be one more surface no hash covers.
- **Multi-round-trip requests are out, by name** (`docs/will-not-implement.md`, entry 12; the
  `BeamMCP.Server` moduledoc): every request is answered completely or refused; the one
  `resultType` written is `"complete"`; `inputResponses` and `requestState` are read nowhere,
  and a request carrying them is served as if it carried neither. A census holds the names
  unread; a nine-case wire test holds the answer unchanged.

### Fixed — a tuple error reason from a host's dispatch is a tool error, not a crash

- A dispatch answering `{:error, {:missing, :window}}` — a tuple reason, the shape this
  package's own refusals take — passed the tuple through to the JSON encoder, whose protocol
  has no implementation for one, and the request crashed. A tuple is now a JSON array on the
  wire (`["missing", "window"]`): in a tool error's `structuredContent.error` and its text,
  and in the `reason` a `resources/read` or `prompts/get` refusal carries as data. Found while
  pinning the connectome tool; any host that returned a tuple reason before got a crash, so
  no working client sees a change.

### Fixed — `Mcp-Name` on `resources/read` and `prompts/get` over HTTP

- The routing table requires `Mcp-Name` on three methods — `tools/call` (`params.name`),
  `resources/read` (`params.uri`), `prompts/get` (`params.name`) — and the transport checked
  it on the first alone, from the day that was the only one served; the other two answered
  `200` without the header. Now all three require it and hold it to the body (`400`,
  `-32020` on a mismatch, as for `tools/call`). Found by a review lane; a client that already
  sends the header sees no change.

### Added — the prompts primitive, on the tools' own validation path

- **`prompts/list` and `prompts/get`**, the two request methods the `2026-07-28` schema
  defines for prompts (`completion/complete` is the separate `completions` capability's and
  is not served; `notifications/prompts/list_changed` is not sent: `listChanged: false`). A
  catalog names prompts as `BeamMCP.PromptSpec` structs, each with `BeamMCP.PromptArgument`s,
  in its existing `prompts` list — no new key — and renders them through a new optional
  callback, `get_prompt/2`, required the moment a prompt is listed. **One validation path:**
  a prompt's argument list is derived into a JSON Schema (`BeamMCP.PromptSpec.argument_schema/1`
  — one `string` property per argument, `required` from the flags, nothing undeclared
  admitted) and validated by the tools validator; the arguments reach `get_prompt/2` keyed by
  the declared names, as a tool's reach its dispatch. A caller's argument name becomes an
  atom on neither path — measured over 10,000 distinct keys through both, the tools path's
  stated bound now a test. An unknown prompt, a missing required argument, an undeclared one
  and a reader's `{:error, reason}` are each `-32602` with data; a malformed reader answer is
  `-32603` by name. Messages are `user` or `assistant` with text content only, as for tools.
  `prompts/list` is paginated by `BeamMCP.Cursor` with `prompts_ttl_ms:` /
  `prompts_cache_scope:` (defaults `0` / `"private"`); `prompts/get` is not cacheable. Both
  eras serve both methods. The official conformance suite's `prompts-list`,
  `prompts-get-simple`, `prompts-get-with-args` and `caching` scenarios pass against the
  harness catalog's two text-only diagnostic prompts and leave the baseline; the
  `2026-07-28` suite row is 16 / 37 (12 / 37 after the resources entry below).
- **How to tell whether you are affected:** if your catalog's `prompts` list carried anything
  other than `%BeamMCP.PromptSpec{}` structs — a map with a `"name"`, which the declared
  connectome read as a node name — `BeamMCP.Server.new/1` now refuses the catalog at startup,
  naming the key; rewrite each as a `%BeamMCP.PromptSpec{name:}` and export `get_prompt/2`. An
  empty `prompts` list is unaffected. The declared connectome names a `%BeamMCP.PromptSpec{}`
  node as it named the map.

### Added — the pages ship in the package

- **`docs/` is in the Hex tarball.** The six pages the README links were absent from the
  package: the connectome vocabulary, the canonical bytes, the observed graph and the diff,
  which 0.4.0 rendered on hexdocs and did not ship; and reach and the will-not-implement
  contract, new in this release. Where that showed: hex.pm's package page renders the README
  with each relative link resolved to the package preview
  (`repo.hex.pm/preview/beam_mcp/<version>/<path>`), which serves the tarball's own files (a
  probe of `mix.exs` there answers 200) — so every `docs/` link on 0.4.0's page was a 404
  (measured); a consumer with the package on disk (`deps/beam_mcp/` after `mix deps.get`) had
  the same dead paths. On hexdocs the links were already rewritten to the rendered pages and are
  unchanged. Now the pages are in the tarball at `docs/*.md`, so both the hex.pm render and the
  on-disk package resolve them, and a test holds it against the **built** tarball rather than
  the `files:` stanza: every file reachable by a relative link (inline, reference-style or an
  HTML `href`) from the README or CHANGELOG, every tracked page under `docs/`, and every ExDoc
  extra must be in what `mix hex.build` produces. The tarball grows by the six pages over
  0.4.0's 21 entries (the modules other entries of this release add — the reach module, the
  resources primitive's two, the cursor codec, the prompts primitive's two and the connectome
  surface, seven — ship beside them, and the count of them was taken from the built tarball at
  the release, not from this file's history; no byte count is stated: this file ships in the
  tarball). No other entry is added or removed by this change.

### Added — the resources primitive, and one pagination codec

- **`resources/list`, `resources/templates/list` and `resources/read`**, the three request
  methods the `2026-07-28` schema defines for resources (its `resources/subscribe` of earlier
  revisions is gone — `subscriptions/listen` replaced it — and is not served; the capability
  is advertised with `subscribe: false` and `listChanged: false`). A catalog names resources
  and templates as `BeamMCP.ResourceSpec` and `BeamMCP.ResourceTemplateSpec` structs in its
  existing `resources` list — one list, two structs, no key twice, so `capabilities/0` gains
  no key — and reads them through a new callback, `read_resource/1`, required the moment
  either is listed. **One reader advertises and decides
  readability:** a `resources/read` uri is served only when the same list names it or a listed
  template matches it (RFC 6570 `{var}` one non-empty segment, `{+var}` across; no other
  expression is claimed, and a template carrying one, or a bare brace, is refused at
  startup), else `Resource not found` with the uri as data before the reader runs — `-32602`
  under `2026-07-28`, which requires it, and `-32002` under `2025-11-25`, which named that
  code (the modern revision says clients SHOULD still accept it). A `params` that is not an
  object, on either list, is `-32602` by name. A reader's `{:error, reason}` is the same
  not-found code with the reason; a malformed reader answer is `-32603` naming the defect,
  never a crash. Blob contents are raw bytes at the reader and
  base64 on the wire; optional fields the specification leaves out are left out, not sent as
  `null`. Both eras serve the three; `2026-07-28` results carry `ttlMs`, `cacheScope` and
  `resultType` as `tools/list` does, from the new `resources_ttl_ms:` and
  `resources_cache_scope:` options with the same non-permissive defaults. The official
  conformance suite's five resource scenarios (`resources-list`, `resources-read-text`,
  `resources-read-binary`, `resources-templates-read`, `sep-2164-resource-not-found`) pass
  against the harness catalog's three diagnostic resources and leave the baseline; the
  `2026-07-28` suite row is 12 / 37 (7 / 37 when the conformance entry below was written).
- **`BeamMCP.Cursor`, the pagination codec every paginated list shares.** Opaque (a client
  passes it back unchanged), stable (one position, one byte string), URL-safe, typed by its list
  (a cursor from another list is refused by name as invalid params), and **keyed on the item's
  canonical key rather than an offset**, so a list that changes between two pages never skips an
  item that was there before and is there still; `nextCursor` is present exactly when more
  remains. The page size is `BeamMCP.Server.new/1`'s `page_size:` (default 50). Both resource
  lists use it; `tools/list` does not yet.
- **How to tell whether you are affected:** if your catalog's `resources` list carried
  anything other than the two structs — a map with a `"uri"`, say, which the declared
  connectome read as a node name — `BeamMCP.Server.new/1` now refuses the catalog at startup,
  naming the key; rewrite each entry as a `%BeamMCP.ResourceSpec{uri:, name:}` and export
  `read_resource/1`. A catalog with an empty `resources` list is unaffected. The declared
  connectome names a `%BeamMCP.ResourceSpec{}` node as it named the map; a template has no
  `uri` and is enumerated as an unreadable entry, not a node.

### Added — reachability, additive

- **Reachability queries over a connectome graph.** `BeamMCP.Connectome.Reach` answers four
  questions about a `BeamMCP.Connectome.Graph`, the declared one being the point: is there a
  path from an entry to an effect (`reachable?/4`); is there one that crosses none of a set of
  gate nodes (`reachable_without/5`), and when there is, a **witness** — a
  `BeamMCP.Connectome.Reach.Path` whose edges are the input graph's own, in order, so a reader
  checks it against the graph rather than trusting the package; does a gate dominate an
  effect from the entry set (`dominates?/4`, the removal definition itself); and which nodes
  every path to an effect must cross (`mandatory_pass/3`, Lengauer–Tarjan — OTP's
  `:digraph_utils` has no dominator function, so it is written here and held to `dominates?/4`
  by a property over every node of generated graphs). On OTP's `:digraph`, one private table
  per query deleted on every exit; **no new dependency**. Edge kinds and a hop limit are
  constraints; signs are not read. `max_edges:` is the one cap, refused by name; `all_paths/4`
  is refused by name, always — enumerating paths is exponential and no cap makes it a
  question this package answers. `docs/connectome-reach.md` is the contract, with the
  measured cost on the gate's 10 000-edge fixture (a search ~14–21 ms, dominators ~22–24 ms),
  recorded by every gate run (`bench/reach.exs`) and judged by no number.
- **`BeamMCP.Connectome.Edge.kinds/0`** — the edge vocabulary from one site.
- **Nothing on the wire changes.** No method, field or capability is added.

### Added — the conformance harness, and a number a stranger can reproduce

- **`tools/conformance.sh` runs the official MCP conformance suite** (`@modelcontextprotocol/
  conformance` 0.2.0-alpha.11, pinned by exact version) against the HTTP transport with the
  harness catalog in `conformance/server.exs`, for each revision's frozen requirement set, and
  prints **two rows per revision** from the suite's own `checks.json`: suite totals (scored
  scenarios passed / scored — the failures not hidden) and claimed-surface totals (over the
  scenarios whose methods and tool names this package claims). Expected failures are baselined
  per revision with a reason word each; the suite exits 1 on a regression and on a stale
  entry. Measured 2026-09-15: `2026-07-28` 7 / 37 and 5 / 6; `2025-11-25` over HTTP 0 / 30 by
  design (HTTP serves `2026-07-28` only; `2025-11-25` lives on stdio, which the suite cannot
  drive). The README carries the rows with their provenance. Needs Node ≥ 22 and python3.

### Changed — BREAKING: the request `_meta` is read where the schema puts it, `params._meta`

- **A request's `_meta` lives in `params._meta`, and nowhere else.** `JSONRPCRequest` has no
  `_meta` property; `RequestParams` requires one in `2026-07-28`, with
  `io.modelcontextprotocol/protocolVersion` and `io.modelcontextprotocol/clientCapabilities`
  inside it. From `0.3.0` to `0.4.0` this package read the message's **top level** — and its
  own tests sent it there — so a spec-following `2026-07-28` client over stdio had its version
  go unread and was answered legacy-shaped while the server advertised modern; over HTTP the
  transport stamped a top-level `_meta` from the header before dispatch, which masked the
  position for every HTTP consumer (measured: the spec's shape, the old shape and no `_meta`
  at all each got a modern result). Now: the core reads `params._meta`; a top-level `_meta` is
  refused with `-32602`, present with or without `params._meta` — the old position is not a
  compatibility mode, because two accepted shapes would be permanent; a `params._meta` without
  `clientCapabilities` on a modern request is `-32602`; over HTTP the header is matched to
  `params._meta`, nothing is stamped, and a request whose `params._meta` is missing or lacks a
  required field is `-32602` with HTTP 400 (SEP-2575). A notification's `_meta` stays optional,
  and a notification is never answered: one carrying a misplaced or version-less `_meta` is
  served as if bare over stdio, and refused with 400 over HTTP where every POST is checked.
  **How to tell whether you are affected:** if your client puts `"_meta"` beside `"method"` in
  the request object, it now gets `-32602 Invalid params: _meta belongs in params._meta`; move
  it inside `"params"` — `{"method": "tools/call", "params": {"name": ..., "arguments": ...,
  "_meta": {...}}}` — and, for `2026-07-28`, include `clientCapabilities` in it. Over HTTP, a
  client that sent no `_meta` and relied on the header now gets `-32602` with 400; send
  `params._meta` naming the same version as the header. Found by the official conformance
  suite's `server-stateless` scenario and by reading the schema it cites.

### Changed — BREAKING: the sign vocabulary — `:unknown` is `:unset`, `:ungoverned` is added, and `schema_version` is `2`

- **The one sign the package writes is `:unset`, not `:unknown`.** It means exactly this: no
  sign has been supplied to this package. It does not mean no policy exists, spoke or was
  computed — a host whose authority plane denied an edge, where that verdict never reached
  this package, gets `:unset` on that edge, and a graph glossing that as "no policy has
  spoken" (the 0.4.0 wording) would be wrong about the world. The graph is what a consumer
  signs, so the word had to be the narrow true one. `BeamMCP.Connectome.Edge.check/1` refuses
  `:unknown` by name.
- **`:ungoverned` is a fifth value, a consumer's:** a consumer looked and no gate applies to
  this edge. The package never treats it as suppression — the diff records the edge exactly as
  any other (a sign appears in the diff record only in a changed-sign entry; every sign is in
  the graph's bytes), and a census holds that no code line filters, hides or downgrades an edge
  by its sign. The bytes carry no field saying which consumer wrote a sign or when. The sign is
  orthogonal to drift: an observed edge nobody declared is `observed_but_undeclared` whatever
  its sign.
- **Changed-sign is two authorities disagreeing.** A label in both graphs is `changed_sign`
  when both signs are supplied — neither `:unset` — and they differ; held over all
  twenty-five pairs. `:ungoverned` against `:deny` is a finding; `:unset` against
  `:ungoverned` is not; `:unset` on both sides never is.
- **Two coverage counts added, `declared_sign_only` and `observed_sign_only`** — labels in
  both graphs with a sign supplied on one side and `:unset` on the other, one count per
  direction because the two directions are different facts (a sign on the observed side
  only means an authority spoke during the run about an edge nobody signed at configuration
  time; the reverse is the odder, and a consumer sees it alone rather than summed). The
  one-sided cases stay out of the classes; they are counts.
- **`schema_version` is `2`** on the graph's bytes (the vocabulary the sign field is read
  against) and, on its own axis, `2` on the diff record (its semantics: changed-sign by name,
  two counts added). Published 0.4.0 bytes at `1` stay exactly as they were and their hashes
  stay verifiable; the version tells a verifier which vocabulary applies
  (`docs/connectome-canonical.md`, *Versions*). `BeamMCP.Connectome.Graph.new/1` refuses any
  version but `2`.
- **How to tell whether you are affected:** if any code of yours pattern-matches, compares
  against, or *writes* `:unknown` into an edge's `sign` — a comparison never holds again
  rather than failing; a write is refused by `BeamMCP.Connectome.Graph.new/1` — reads
  `"sign":"unknown"` out of the bytes, enumerates the sign strings as a closed set (it now
  meets `"unset"` and `"ungoverned"`), builds a `%BeamMCP.Connectome.Graph{}` with
  `schema_version: 1`, or checks a diff record for `"schema_version":1`, it breaks; replace
  `:unknown` with `:unset` and each version with `2`. Bytes you have already hashed and
  stored are unaffected. A diff record re-derived over the same two graphs hashes differently
  from a stored 0.4.0 one: its `coverage` gained the two counts and its version moved. On the
  graph's bytes no other value, field or order moved.

### Changed — on the wire, in `server/discover` and in what a transport advertises

- **`server/discover` returns the `2026-07-28` `DiscoverResult` in full.** The schema requires
  `cacheScope`, `capabilities`, `resultType`, `supportedVersions` and `ttlMs`; the result was
  undecorated — a probe shortcut carried since `0.3.0`, called a known gap in the README — and
  a client reading it had grounds to classify the server as legacy. Now: `supportedVersions`
  (the field was named `protocolVersions`), `resultType: "complete"`, `ttlMs: 0` and
  `cacheScope: "private"` (nothing is cached; the non-permissive default), and the server's
  identity in `_meta["io.modelcontextprotocol/serverInfo"]` rather than a `serverInfo` body
  field, which spec PR #3002 removed. Found by the official conformance suite's
  `server-stateless` scenario, run against the package for the first time.
- **A transport advertises only the revisions it serves.** `BeamMCP.Server.new/1` takes
  `supported_versions:`; the HTTP transport, which refuses every revision but `2026-07-28` on
  every POST, passes exactly that, so its `server/discover` says `["2026-07-28"]` and its
  `-32022` error lists the same — it had listed `2025-11-25` while refusing it. A revision not
  advertised is not served either. Dual-era is a stdio fact; stdio advertises both, as before.
- **`-32022`'s `data.requested` is a string over HTTP**, the version the client asked for
  (the first value refused when several were sent), as the schema says; it was a list.

### Added — the boundary, written down and held to the tests

- **`docs/will-not-implement.md`**: eleven things this package will never do (a twelfth, the
  multi-round-trip request, joined them in the connectome entry above) — populate a sign, hold a
  key, make a signature, decide authority, put a payload byte in the observed graph, claim a
  capability the specification does not define, issue or honour a session identifier, carry
  OAuth, be a client, enumerate all paths or match motifs, hold a tool, a domain or a catalog —
  each with its reason in a line and the test that enforces it, by path and by name. The tests
  are the proof; the page is the contract. The README's *Deliberately out* paragraph points at
  it.
- **Eleven censuses under `test/beam_mcp/boundary/`** (the twelfth is the connectome entry's) put a test behind the six entries that had
  rested on reading (no key material and no `:crypto` call but `hash/2`; no signing or MAC
  primitive and no `sign` function; the advertised capability keys a subset of each revision's
  `ServerCapabilities`; no `Mcp-Session-Id` emitted, honoured or read; no OAuth, no client
  module, no outbound connection, `initialize` only ever received), one behind the thesis (no
  module under `lib/` implements `BeamMCP.Catalog`, none builds a tool), one behind the acts of
  authority in the spellings code uses (`risk_tier`, `approved`, `masked`), one behind the reach
  refusals (`all_paths` defined once, as the refusal; no motif matcher), one behind the reader
  itself (nothing compiles into the application from outside `lib/`, in the source and in the
  built artefact), one behind every other census (no code evaluated and no module, function or
  atom built at runtime, by name), and **one over the artefact itself**: `:xref` over the
  compiled beams pins exactly the modules the package calls, the functions it calls on the
  modules that could reach code, secrets, the OS or another node, and the one atom it makes from
  a binary — a call under any spelling resolves to the same edge, so a new library, evaluator,
  socket, shell, remote spawn, key store or environment read fails until it is named. One reader
  over `lib/**/*.ex` for the text censuses; the tool-construction census reads the compiled
  forms, where the struct's atom may occur only in a map pattern. Each was shown red by a
  planted violation. `Plug.Crypto`, in the lock file through `plug`, is barred by name.
- **A README pin repaired, test-only**: "the observed graph carries edge identity only, never
  a payload byte" sent its marker to a tool with no schema, where argument normalisation
  dropped it before dispatch — the assertion held nothing. It now uses the catalog whose tool
  declares the key and requires the dispatch to have seen the marker first.
- **The page and the tests are one population**: `test/beam_mcp/will_not_implement_test.exs`
  fails when the page cites a test that does not exist by path or by name, when a test marked
  `# boundary:` is not cited, and when a file under `test/beam_mcp/boundary/` carries no mark.
- **Nothing on the wire changes.** No method, field or capability is added; the capability
  census pins that none is.

### Fixed — test suite only

- The Livebook exports fixture ran its collector without a lock; two async test modules
  exporting at once saw each other's `fx` calls and exported doubled weights, a one-in-many
  flake first seen in a mutation pass and then reproduced deterministically with two tasks.
  The collector run is serialised across the node (`:global.trans/4`, the requester being
  the caller). Nothing shipped changes.

## [0.4.0] — 2026-09-14

### Added — the connectome, additive

- **The connectome vocabulary and data model.** `docs/connectome.md` defines the words: a
  connectome is the wiring diagram of a composed MCP system, built once from what is declared
  and once from what ran. `BeamMCP.Connectome.Node`, `BeamMCP.Connectome.Edge` and `BeamMCP.Connectome.Graph` carry it: a node has
  a structural id derived by one function from the identity the host supplies; an edge carries
  from, to, kind, provenance, an optional weight, and a sign slot. **The package writes
  `:unknown` into that slot and nothing else** — it populates no sign, signs no finding, holds
  no key, decides no authority; that is the host's, and a census test over `lib/` holds it.
  `BeamMCP.Connectome.Graph.new/1` validates every struct it is handed, by field, and corrects nothing.
- **The declared connectome.** `BeamMCP.Connectome.Declared.build/1` reads three sources and
  nothing that ran: the catalog's `capabilities/0`, the call edges of the modules in scope from
  their beams (OTP's `:xref`, so a module whose only use is at a macro's expansion site produces
  no edge, and the calls a macro body makes at expansion time are filed as expansion calls, not
  edges), and a grouping of modules at the `:boundary` level. Beside the graph it returns the completeness
  bound — every dynamic-dispatch site, callee outside the scope, unreadable catalog entry, tool
  without a module, and module without a beam or debug information, enumerated and never
  summarised to a count. What the compiled code cannot show is stated in the moduledoc: a
  module handed as data to a dispatcher outside the scope, and calls to the runtime's
  built-ins. A catalog the package's own contract check refuses is refused by the builder for
  the same reason, and never read. OTP's `tools` application, which carries `:xref`, is
  declared optional in the `.app` file — in the one spelling Mix honours, `tools: :optional`
  inside `extra_applications`, with a test that reads the `.app` the build writes — so a release
  without it still boots and the builder refuses by name.
- **Canonical bytes, a hash, and exports.** `BeamMCP.Connectome.Canonical.encode/1` writes the
  declared form of a graph as canonical JSON — schema version first, nodes by id, edges by key,
  every other object's keys in RFC 8785 order, strings NFC-normalised, every atom a string under
  the name of its field, no weight — and `hash/1` is SHA-256 over those bytes. The byte layout is
  specified in full in `docs/connectome-canonical.md`, with a worked example whose hash reproduces
  with `sha256sum` alone, so a verifier can be written without importing this package. Weights
  travel in a separate sidecar that is never hashed. `to_dot/1`, `to_graphml/1` and `to_json/1`
  render the same canonical order. What has no canonical bytes is refused by name rather than
  guessed at: a float, two ids or two label keys that coincide after normalisation, and a string
  that is not valid UTF-8; and, by `to_graphml/1` alone, a character XML 1.0 cannot carry.
- **The observed connectome: a span on the dispatch path, a collector, a guarded tracer.**
  `BeamMCP.Server` emits `[:beam_mcp, :dispatch, :start | :stop | :exception]` in
  `:telemetry.span/3`'s shape around the host's dispatch function — metadata `server_name` and `tool`,
  plus `outcome` on stop; no argument, result or header bytes — and `:telemetry` is a new
  required dependency (Apache-2.0, no dependencies of its own). `BeamMCP.Connectome.Observed`
  is a process the host adds to its own tree: it turns every attempt into one row keyed by
  edge identity, bounded by distinct edges and never by calls, written from the caller's
  process into a public table; `snapshot/1` is a graph with `provenance: :observed` and every
  sign `:unknown` on the declared side's ids, and is a named refusal, `{:error, :not_started}`,
  when nothing is watching. `BeamMCP.Connectome.Tracer` is off by default, one at a time,
  stops itself at its limits, and writes module-to-module and name-to-name edges with the
  `:arity` flag and without reading a message. `docs/connectome-observed.md` is the contract.
- **The diff engine.** `BeamMCP.Connectome.Diff.run/3` takes the declared and the observed graph
  and a window the consumer supplies, and puts every edge of either in exactly one of four classes
  — declared-and-observed, declared-never-observed (dead authority), observed-but-undeclared (a
  drift finding), changed-sign (both signs supplied and different) — with a coverage bound as
  eight counts the consumer divides, among them completeness with the connectomics roles kept
  (observed edges between declared parts, over what ran) and its dual, endpoint coverage. The diff is a set difference over edge labels (from, to, kind),
  never an isomorphism, and says why. Its record has canonical bytes through
  `BeamMCP.Connectome.Canonical.encode_value/1` — the label grammar of a node's labels object,
  applied to a record on its own, so a consumer's verifier reads it unchanged — and
  `docs/connectome-diff.md` is the contract, with a worked example that reproduces with
  `sha256sum`.
- **`BeamMCP.Stacktrace.arities/1`** — the one rewrite that turns a stacktrace's argument lists
  into arities and its locations into what the compiler writes, used by the `:exception` event
  and by the HTTP transport's fault log, which had logged a dispatch's stacktrace untouched —
  a caller's arguments in the host's log.
- **`BeamMCP.Server.new/1` refuses every wrong or unknown option by name at construction** —
  `server_name`, `dispatch`, `dispatch_opts`, `tools_ttl_ms`, `tools_cache_scope`, a typo —
  the way it already refused a malformed catalog; before, a non-string `server_name` was held
  and raised inside the connectome's id derivation at snapshot time.
- **The gate reads the branch's own commit messages** for attribution trailers, session links,
  board identifiers and consumer names — offline, over `origin/main..HEAD`; a pull request's body
  is read by a person before merge.
- **No MCP capability is claimed.** Neither protocol revision this package targets defines a
  topology or declared-reachability primitive, and none is invented. Nothing on the wire changes.

### Added — the Livebook, and the instruments the release is measured with

- **A Livebook renders the connectome from its JSON export alone.**
  `livebooks/connectome.livemd` draws the declared graph, the observed graph with its sidecar
  weights, and the diff coloured by class, and divides the coverage counts the way the diff
  page says a consumer does. It installs Kino and a JSON decoder and no `beam_mcp`, so a reader
  with only the export sees what a reader with the package sees. The four exports beside it are
  held by a test, byte for byte, to what the package produces from its fixtures today;
  `tools/livebook_eval.exs` evaluates the cells outside Livebook.
- **Three gate steps, and a population that cannot be forgotten.** `bench` measures the
  collector's per-call overhead against a ceiling of 1.5 µs per `tools/call` — the owner's
  number, with its reasoning in `bench/overhead.exs`; a ceiling on an optional, off-by-default
  feature, not a performance promise — and records the diff engine's cost on a 10 000-edge
  fixture, for which no threshold is set. `properties` runs the property tests alone at a
  thousand generations each (`PROPERTY_RUNS`, read by the test helper). `instruments` parses
  every tracked shell and Python file. And the format step's population is the tracked set,
  not a glob: the scripts under `tools/` sat outside the old one, and a broken tracked
  instrument passed the whole gate green (measured before the change; named after it).
- **The documentation is held to the code by a census.** Every `BeamMCP` module and function
  the README, the pages, the notebook and the compiled `@doc`s name must exist at that arity,
  a bare name resolved against its own module as ExDoc resolves it. Nine names that read as
  one module's functions but were another's, or a hook's, are qualified. ExDoc groups the
  modules by namespace.

### Changed — BREAKING, and it breaks a host contract rather than the wire

- **`BeamMCP.ToolCatalog` is replaced by `BeamMCP.Catalog`, and `all/0` by `capabilities/0`.**
  Every host implementing a catalog must change. While this package is `0.x` a break lands at
  the **minor** position, so this is `0.4.0` and `~> 0.3.0` — the requirement the README
  recommends — already excludes it. No consumer is carried across by a routine
  `mix deps.update`; that is what the tight pin is for.

  `capabilities/0` returns `%{tools: [ToolSpec.t()], resources: [], prompts: []}`. `resources`
  and `prompts` are **required and may be empty**. Nothing reads them yet. They exist so that
  serving resources and prompts later adds a reader rather than changing this contract a second
  time — the break is taken once, now, before those slices exist.

  **The callback is renamed, not just re-typed.** Keeping `all/0` while changing its return from
  a list to a map would compile against every existing host and fail at the first request with a
  `BadMapError`. Renaming makes the break arrive at compile time as an unimplemented callback.

  The option is `:catalog`, not `:tool_catalog` — a catalog carrying resources and prompts is
  not a tool catalog, and renaming it in the same break costs less than a second one later.

  **Migration:**

  ```elixir
  # before
  @behaviour BeamMCP.ToolCatalog
  def all, do: [%BeamMCP.ToolSpec{...}]

  # after
  @behaviour BeamMCP.Catalog
  def capabilities, do: %{tools: [%BeamMCP.ToolSpec{...}], resources: [], prompts: []}
  ```

- **A malformed catalog is refused by `BeamMCP.Server.new/1`**, at startup, with a message naming
  what is wrong — an absent key, a non-list `:tools`, an entry that is not a `%ToolSpec{}`, a
  `capabilities/0` that does not return a map, or a module that does not export it.
  The HTTP transport's `init` callback checks only that the hook is exported, deliberately: under Plug's
  default initialisation it runs at the host's **compile** time, where calling a catalog that
  reads config would fail for a correct host.

### Added

- **`:authorize_body`, an optional post-read authorization hook.** `authorize/1` runs before the
  request body is read — which is what lets it refuse an unauthenticated caller without
  buffering megabytes on their behalf — and the cost of that position is that it cannot see the
  body. Body-signature authentication was therefore not merely awkward through it but
  structurally impossible: there was no argument through which the bytes arrived.

  `:authorize_body` is `(Plug.Conn.t(), binary() -> :ok | {:error, term()})`, called after the
  body is read and before it is decoded. **The second argument is the request body exactly as
  received**, not a re-encoding: a signature covers bytes, so a hook handed
  `Jason.encode!(Jason.decode!(body))` would reject every correct signature while presenting as
  a fault in the host's cryptography.

  **Additive and optional.** Absent, it is skipped and nothing changes; `authorize/1`'s arity,
  position and semantics are untouched, so no existing host is affected. Present, it must be a
  2-arity function or `init/1` raises — a wrong arity is a startup failure, not a per-request
  one. A refusal answers `403` and a raising hook `500`, both opaque: the reason goes to the
  log, never to the caller, so a client cannot distinguish "no signature" from "bad signature".
  A post-read refusal does **not** carry `connection: close`, because by then the body is read
  and the connection is clean.

  **This package performs no cryptography.** The option is named `:authorize_body` rather than
  `:verify_signature` because verifying is the host's work; making it possible is this module's.

## [0.3.1] — 2026-09-08

Five defects in the HTTP transport. Four were found by slice 002's review lanes and filed rather
than fixed at the time; the fifth was found by this slice's own review and fixed here rather than
tagged around, because it is unauthenticated and attacker-reachable. No wire break: `~> 0.3.0` admits this release and still excludes the
next one, measured with Elixir's own `Version` module rather than recalled. The whole row, not
an extract of it — an abridged quotation is not a quotation:

    requirement   0.1.0    0.2.0    0.3.0    0.3.1    0.4.0    1.0.0
    ~> 0.3.0      false    false    true     true     false    false

Written by the run that produced it, in
`slices/003-release-0-3-1/logs/measure-version-requirement.txt` **in the repository — slice
records are not shipped in the package**, and the same is true of every `slices/…` path below.

### Fixed

- **An `x-mcp-header` annotation on a non-primitive parameter is the host's fault.** The
  revision allows the annotation only on `integer`, `string` and `boolean`, and
  `value_matches?/2` assumed that MUST rather than checking it — so an annotated `number`,
  `object` or `array` could never match any header. Omitting the header was refused as
  *"required: the body carries a value to mirror"* and supplying one as *"does not match"*: the
  tool was advertised through `tools/list`, was permanently uncallable, and the `400` blamed the
  caller for the host's schema. It is now `500` with `-32603`, the diagnosis goes to the log
  naming the tool and the annotation, and nothing about it reaches the caller. A property with
  no declared type is left alone.

- **Colliding `x-mcp-header` names are refused rather than silently collapsed.** The revision
  requires the values to be case-insensitively unique. The annotation set was accumulated into a
  map keyed by the case-folded name, so `Dup` and `DUP` collapsed to one entry — `Map.put` lost
  the sibling and a nested annotation could overwrite an outer one. One annotated property was
  then never checked at all, and which one survived depended on map iteration order. The set is
  now a list keyed by nothing, and a collision is refused as a host fault like the above.

- **A host catalog returning a malformed spec now answers with the request's id.** A host
  catalog that *raised* was answered inside the envelope with the id; the same host catalog
  returning a spec-shaped map that is not a `%ToolSpec{}` raised `KeyError` on the
  `spec.input_schema` read one line later, escaped to the outer rescue and answered `id: null`.
  One host bug got two envelopes depending on which line it landed on. The spec read, the schema
  walk and the annotation check now all sit inside the same guarded call.

- **A header value that is not valid UTF-8 is refused, not reflected.** `MCP-Protocol-Version`
  carrying invalid UTF-8 was echoed back in the refusal's `data.requested`, so `Jason.encode!`
  raised inside `send_json/3` — outside every inner rescue — and the caller's own `400` became a
  `500` with an error-level stacktrace in the host's log. Unauthenticated and attacker-reachable:
  no credential is needed to send a header. The refusal now happens at the read, in
  `header_values/2`, which every header read in the transport routes through — so it covers
  `Origin`, `Mcp-Method`, `Mcp-Name` and every `Mcp-Param-{Name}` as well, and a header read
  added later inherits it. The offending bytes are named as a header, never reproduced in the
  response.

- **A refusal issued before the request body is read carries `connection: close`.** Only the
  `413` did. The other six pre-read refusal sites — the `Origin` `403`, the `405`,
  `authorize/1`'s `500`, its `403` and its contract-violation `403`, and the body read's own
  `400` — answered on a connection whose body was still on the wire and said nothing about it,
  so the adapter read that body anyway on behalf of a caller already refused (`Bandit` drains
  up to 8 MB, waiting up to its read timeout), and past that limit dropped the connection with
  nothing said to the client. All seven now answer through one path, so a step added in front
  of the body read inherits the behaviour. A refusal issued *after* the body is read keeps the
  connection.

### Known gaps

Recorded rather than fixed, with the measurement, in `slices/003-release-0-3-1/FINDINGS.md`:

- **`fault_response/4`'s re-raise branch is still unpinned.** Unchanged by this release.
- **`read_body_bounded/1`'s `{:error, reason}` `400` has no test**, and now carries the new
  close behaviour untested with it.

## [0.3.0] — 2026-09-07

### Added — stateless Streamable HTTP transport

`BeamMCP.Transport.HTTP` is a `Plug` serving `2026-07-28` at one endpoint. Every request stands
alone: **no sessions, no `Mcp-Session-Id`, no SSE resumability**, all three removed from the
transport in that revision. `handle_message/2` gains no clause — HTTP is a second caller of the
existing core.

`plug` and `bandit` are **optional** dependencies, so a host using only stdio does not pull an
HTTP server into its tree.

**Two options have no defaults, and a host that omits either cannot start.**

    Bandit.child_spec(
      plug: {BeamMCP.Transport.HTTP,
             tool_catalog: MyApp.Catalog,
             dispatch: &MyApp.Dispatch.call/3,
             authorize: &MyApp.Auth.check/1,                  # required, no default
             allowed_origins: ["https://app.example.com"]},   # required, no default
      port: 4000, ip: {127, 0, 0, 1})

This package cannot decide who may call your tools — it has no view of your identity model, and
deciding for you would be claiming something it cannot keep. But a Plug that serves `tools/call`
to anyone who can reach the port is a confused-deputy surface, and "the host should have
authenticated" is documentation rather than a control. **A required argument with no default is
a contract**, because you cannot start without answering it. To accept every caller, say so
explicitly: `authorize: fn _conn -> :ok end`.

`allowed_origins` exists because the specification makes validating `Origin` a MUST, to prevent
DNS rebinding. `:any` is available and must be chosen deliberately.

**What the transport enforces**, each a MUST of the transport specification:

| requirement | behaviour |
|---|---|
| `MCP-Protocol-Version` on every POST | missing -> `400`, `-32020` |
| header must match the body's `_meta` | mismatch -> `400`, `-32020` |
| `Mcp-Method` on every request (**not** on notifications, which the revision leaves undefined) | missing or mismatched -> `400`, `-32020` |
| `Mcp-Name` on `tools/call` | missing or mismatched -> `400`, `-32020` |
| `Mcp-Param-{Name}` for every parameter the tool's schema marks `x-mcp-header` | mismatched, or omitted while the body carries the value -> `400`, `-32020` |
| an encoded header value is decoded before comparison | `=?base64?…?=`, on `Mcp-Name` and `Mcp-Param-{Name}` **only** — the two headers the specification scopes it to |
| `initialize`, `notifications/initialized`, `ping` | `404`, `-32601` — deleted by this revision |
| unsupported version | `400`, `-32022` |
| invalid `Origin` | `403` |
| unknown **method** | `404`, `-32601` |
| unknown **tool** | `200` with `-32601` in the body — a live endpoint, a bad argument |
| non-POST (a SHOULD, not a MUST) | `405` with `Allow: POST` |

The mirrored-parameter population is derived from **the tool's `inputSchema`**, not from the
headers the caller sent. The specification's fourth server-behaviour row is *"client omits header
but value is in body → server MUST reject"*, which is unenforceable if the caller's own headers
define what gets checked; and `x-mcp-header` carries a header **name portion** pointing at a
property path that may be nested, so the mapping cannot be recovered by lowercasing a header
suffix into a top-level argument key.

**Every header is validated in all of its values, not the first.** A duplicated header — a
satisfying value followed by a hostile one — is the same smuggling the MUST above exists to
stop, and the first version of this transport read only the first value of four of them. There
is now one read path, `header_values/2`, and one mutant per header proving each is pinned
(`slices/002-streamable-http/logs/mutation.md`, in the repository — slice records are not shipped in the package).

`Mcp-Method` and `Mcp-Name` are validated against the body because the specification says why:
*"a load balancer routing on the header value while the MCP server executes based on the body
value."* An earlier draft of this table omitted both while calling itself a list of MUSTs, and a
reviewer demonstrated the consequence — `Mcp-Method: tools/list` with a `tools/call` body
returned `200` and reached dispatch.

**What this closes.** On stdio a `tools/call` with no handshake and no `_meta` is served —
defensible there, because whoever can write to that transport already has the host's privileges.
Over HTTP that argument does not hold, and the specification removes the case: the version header
is mandatory, so a request with no era established is *malformed* and refused as a protocol
matter rather than a policy choice.

### Added — `ttlMs` and `cacheScope` on `tools/list`

`2026-07-28` requires both via `CacheableResult`. No release before this one emitted them.

Neither is the package's to invent: `ttlMs` is a freshness hint about a catalog the host owns,
and `cacheScope` is a disclosure decision — `"public"` lets shared intermediaries cache a tool
list, and a tool list can be sensitive. Both are host-supplied through `tools_ttl_ms:` and
`tools_cache_scope:`, and **the default is the non-permissive one** (`0` and `"private"`). A
package that picked the permissive default on a host's behalf would be making a disclosure
decision it cannot keep.

### Known limitation — `authorize/1` cannot see the request body

It runs **before** the body is read and returns `:ok | {:error, reason}`, with no way to hand back
the `conn` it read from, so **body-signature authentication — an HMAC over the payload — is not
possible in it**. This does not fail as an error: a small request appears to work because the body
is already in the adapter's buffer, and a larger one hangs until the server's read timeout and
returns `408` with the connection dead (measured: 119 bytes `200`; 16 KiB and 200 KiB both `408`
at 15.0 s). A host that meets this by experiment would reasonably read it as a bug, so it is
written down.

Today: authenticate in a plug in front of this one that reads the body and re-supplies it, or
decide in `dispatch/3`, which is handed the decoded arguments. **This is an open design question,
not a final shape.** The likely answer is two hooks — `authorize/1` staying as the cheap pre-read
gate on headers, origin and peer, plus an optional post-read hook for body signatures — and that
belongs in its own release rather than in one that is otherwise finished. Designing an
authentication contract under release pressure is how the wrong one ships permanently.

### Changed — the recommended dependency requirement

`README.md` now recommends `{:beam_mcp, "~> 0.3.0"}`. `~> 0.3` admits `0.4.0`, and this package
documents wire breaks at the **minor** position while it is `0.x`.

### Changed — a host's exception no longer chooses the HTTP status

**Read this if a host tool, `authorize/1` or `tool_catalog` raises an exception carrying a
`:plug_status`** — `Plug.BadRequestError`, or Ecto's `NoResultsError` at 404, for instance. In
`0.2.0` there was no HTTP transport, so this is new behaviour rather than changed behaviour, but
it changed twice during this release and the second shape is what ships:

    a host tool raising Plug.BadRequestError
      -> HTTP 400, empty body, no JSON-RPC error object
    now
      -> HTTP 500, {"jsonrpc":"2.0","id":<the request id>,"error":{"code":-32603,...}}

An exception carrying a status means the **server** is signalling — Bandit raises
`Bandit.HTTPError` for a malformed transfer coding and its pipeline turns that into the response.
An exception out of **host** code carries no such authority however it is annotated, and letting
it through dropped the envelope on a path the protocol requires one, with no `id` to correlate
and no body to parse.

The rule is applied at every point host code runs in the request path — `authorize/1`,
`BeamMCP.ToolCatalog.fetch/2` and `BeamMCP.Server.handle_message/2` — and that population is
derived by grep rather than listed, because listing it is how the first cut of this fix covered
one of the three and shipped a comment claiming all of them.

**The `id` is echoed on some of these limbs and not others, and the diagram above shows only
the common case.** Measured:

    host tool raises (dispatch/3)                    500  -32603  id echoed
    host tool_catalog RAISES (header validation)     500  -32603  id echoed
    host tool_catalog returns a malformed spec       500  -32603  id null
    host authorize/1 raises                          500  -32603  id null

`authorize/1` runs before the body is read, so there is genuinely no id to echo. The malformed-
spec case is different and is an inconsistency rather than a necessity: the spec is read at
`annotations(spec.input_schema)`, which sits outside `host_call/1`, so a host DATA fault escapes
to `call/2`'s rescue where the id is not known — while a host RAISE two lines earlier is caught
and answered with it. Recorded rather than fixed here, because moving that read inside
`host_call/1` changes which rescue answers and wants its own red.

### Added — `BeamMCP.ToolCatalog.fetch/2` is public API

One lookup answers "which tool does this name mean" for both the core and the HTTP transport's
header validation. Two lookups would be two answers, which is the disagreement the mirrored-header
mechanism exists to prevent. Its `@spec` says `{:ok, t} | :error` and three host-authored catalog
shapes raise instead; that is filed, not fixed here.

### Fixed — two failure modes found by measuring rather than by reasoning

- **A failure in the host's dispatch answered with an empty `500`.** It now answers
  `-32603 Internal error` **carrying no detail**; the reason still reaches the logger, where the
  host can see it. Leaking it to an HTTP caller would hand a possibly-unauthenticated party the
  host's internals.

  The first fix used `rescue`, which catches raises only. A reviewer showed `throw` and `exit`
  still producing the bare empty `500` this entry claimed had been eliminated — and `exit` is
  the shape that matters most, because **a `GenServer.call` timeout exits**, which is what a
  host calling a backend hits first. Now `catch`, covering all three.

- **`BeamMCP.Transport.Stdio` was documented.** It carried `@moduledoc false` — inherited from
  the tree it was extracted from, where it was internal — while `README.md` documents `run/1` as
  the entry point. Left alone, `0.3.0` would have published hexdocs in which the stdio transport
  is absent and the new HTTP transport beside it renders, which reads as deliberate.

  **This is the second instance of one defect: `BeamMCP.Server` shipped hidden in `0.1.0`.** The
  entry recording that one also recorded why nothing caught it — "a hidden module is not a
  compile warning and the gate does not run `mix docs`" — and the gate still did not, for two
  more releases. So `tools/gate.sh` now has a `docs` step, and it reads `mix docs`'s **output**
  rather than its exit code, because `mix docs` exits `0` on a warning:

      docs    FAIL (exit 0, 6 warnings)

  That line is from the probe in `slices/002-streamable-http/logs/probe-docs-gate.txt`, which
  reverts the moduledoc, shows the gate red, and restores it. Fixing an instance twice and the
  mechanism never is what the step is for.

- **The `403` for a refused caller carried the host's refusal reason.** `authorize/1` returns
  `{:error, term}`, and that term was `inspect`ed into the response body — on the one branch
  that is by definition unauthenticated. A reviewer recovered a planted bearer token and a
  database URL from it. The reason now goes to the log; the caller is told only `Forbidden`.

- **A non-map `_meta` crashed outside the rescue**, giving the same bare empty `500`. `_meta` is
  any JSON value once the body is an object, and reaching into a string raised in `Access.get/3`
  before the handler was entered. Now a `400`.

- **Five error paths poisoned the next request on a keep-alive connection**, and the first
  diagnosis of this was wrong in a way worth recording. It was reported here as a `413`
  problem. A reviewer could not reproduce it on `413` — and was right, because `413` already
  carried the updated connection out. The real defect was one level up: `with/else` clauses
  cannot see bindings made inside the `with`, so **every refusal after the body was read
  answered on the pre-read connection**. Bandit then framed the next request's bytes as this
  one's unread body, and the following request hung.

  Affected: missing protocol header, header mismatch, unsupported version, invalid JSON and
  non-object JSON. It is **size-dependent** — a few dozen bytes arrive in a single adapter read
  and look correct — which is why every test and every row of the first resilience table passed
  while five paths were broken. Found with a 16 KB body and two requests on one socket.

  Now every step returns the connection it was handed and every refusal answers on that one.
  Verified over a raw socket at 16 KB: all five paths answer, and the following request on the
  same connection returns `200`.

Request bodies are capped at 1 MiB. Without a cap, a body is an unbounded allocation an
unauthenticated caller controls.

## [0.2.0] — 2026-09-07

### Changed — two fields are REMOVED from results for legacy-declared requests

**Read this before upgrading if any client sends `_meta` naming `2025-11-25`.** A result
answering such a request no longer carries `resultType` or `_meta`
`io.modelcontextprotocol/serverInfo`. In `0.1.0` it carried both. This is not limited to
`ping` — it applies to every method reaching that path, `tools/list`, `tools/call` and
`shutdown` included:

    0.1.0:  tools/list + _meta 2025-11-25
      -> {"result":{"_meta":{"io.modelcontextprotocol/serverInfo":{...}},"resultType":"complete","tools":[...]}}
    0.2.0:  tools/list + _meta 2025-11-25
      -> {"result":{"tools":[...]}}

A client that reads `result.resultType` on that path gets `nil`. **That is why this is `0.2.0`
and not a patch.**

The argument for a patch was available and is rejected: `0.y.z` sits outside semver's
compatibility contract, and the removed fields were never correct — they announced a revision
the client did not ask for. Neither of those makes the wire change smaller. For a published
package the JSON *is* the API. For a client declaring `2025-11-25`: **a method that was
refused now answers** (`ping`), and **results on that path have lost two fields**. A `0.1.0`
consumer could have depended on either.

The field removal is the breaking-shaped half and is the whole case for the bump; the `ping`
change is additive and is not an argument for it.

**This paragraph had the direction backwards and it is worth saying where that came from.** It
read "a method that answered now refuses", which is true of no method in this release. That
sentence was one of the two grounds given for choosing `0.2.0`, and it travelled from the
decision through to this file without anyone checking it — the second ground, the field removal,
is correct and carries the decision on its own. A reviewer caught it by enumerating every method
for a client declaring `2025-11-25` on both this tree and `0.1.0`'s, rather than by reading any
of the places it was written down:

    ping         0.1.0: REFUSED -32601      0.2.0: answered
    every other method: unchanged status on both

Recorded rather than quietly reworded, because a false statement about wire behaviour in a
published package's changelog is the paragraph a consumer reads to decide whether to upgrade,
and because the correction strengthens the case for `0.2.0` rather than weakening it. The minor bump is the honest signal, and the
`### Changed` heading above stays exactly as it was written when the number still disagreed
with it.

Owner decision, 2026-09-07.

Requests declaring `2026-07-28`, and requests with no `_meta` at all, are unaffected.

### Fixed

- **A request declaring `2025-11-25` through per-request `_meta` is now served as
  `2025-11-25`.** The `_meta` clause branched on the method and never on the declared
  revision, so `ping` was refused with `-32601` at every revision reaching it, and every
  result was decorated with `resultType` and `_meta` `serverInfo` — two fields `2026-07-28`
  introduced and `2025-11-25` does not define. Both halves came from one version-blind `cond`.

  Measured against `0.1.1`, each message the first and only one on a fresh state. (`0.1.1`
  here and `0.1.0` above name the **same** before-state: `0.1.1` changed documentation only,
  so the version-blind clause is byte-identical at the `v0.1.0` tag and on `main`. Two numbers
  for one behaviour, flagged by review as a readability trap.)

      ping + _meta 2025-11-25   ->  {"error":{"code":-32601,"message":"Method not found: ping"},...}
      tools/list + _meta 2025-11-25
        ->  {"result":{"_meta":{"io.modelcontextprotocol/serverInfo":{...}},"resultType":"complete",...}}

  and after:

      ping + _meta 2025-11-25   ->  {"id":1,"jsonrpc":"2.0","result":{}}
      tools/list + _meta 2025-11-25  ->  {"result":{"tools":[...]}}          # no resultType, no _meta

  Live in published `0.1.0`. The refusal is reachable only through `_meta`: a bare `ping`, and
  a `_meta` carrying no `io.modelcontextprotocol/protocolVersion`, were always answered.

  Why a `_meta` may name the legacy revision at all: this server advertises `2025-11-25` in
  `server/discover` and lists it in the `-32022` `supported` payload, and the specification
  tells a client receiving `-32022` to select from `supported` and **retry the request** —
  which produces exactly this message. `_meta` fixes statelessness; the revision it names
  fixes the semantics.

### Note on `0.1.1` — why the published versions jump `0.1.0` -> `0.2.0`

**`0.1.1` does not exist as a release and never will.** It reached `main`, was never published
to Hex, and `mix.exs` now reads `0.2.0`. Its one change — a moduledoc for `BeamMCP.Server`,
which shipped hidden in `0.1.0` — **ships inside this release**, and its entry is kept below
under its original heading rather than being folded up or deleted.

So a reader comparing Hex to this file sees `0.1.0` then `0.2.0`, with a `0.1.1` section in
between that names no release. That is the whole explanation, stated here rather than left as a
gap to be reconstructed: the number was taken on `main`, the release it was taken for never
happened, and the work it covered is in `0.2.0`.

The `0.1.1` section below is left exactly as written. This note is appended rather than a
rewrite, per the corrections-are-appended rule.

## [0.1.1] — unreleased

> **This version does not exist and never will, and from `0.3.0` this file is published on
> hexdocs, so that sentence now needs to be visible here rather than only in the note above.**
> `0.1.1` was numbered on `main`, never released, and its one change shipped inside `0.2.0` —
> verifiable without leaving the registry: `BeamMCP.Server` renders at
> `hexdocs.pm/beam_mcp/0.2.0` and 404s at `0.1.0`. The heading is left as written, per the
> corrections-are-appended rule; this note is the correction.


### Fixed

- **`BeamMCP.Server` is documented.** It carried `@moduledoc false`, so hexdocs rendered the
  package's principal module as hidden and the two warnings below were emitted on every build.

### Was known, now fixed

**Two hexdocs warnings**, reproduced by running `mix docs` rather than taken from the publish
output:

    warning: documentation references module "BeamMCP.Server" but it is hidden
    warning: documentation references module "BeamMCP.Server" but it is hidden

`BeamMCP.Server` carries `@moduledoc false` — inherited verbatim from the tree it was extracted
from, where it was an internal module and the annotation was correct. It is now the package's
principal public module, and `BeamMCP.ToolCatalog`'s docs link to it, so the published docs
reference a module hexdocs will not render. The annotation stopped being true the moment the
code left the umbrella, and nothing caught it because a hidden module is not a compile warning
and the gate does not run `mix docs`.

## [0.1.0] — 2026-09-06

First release. Tag `v0.1.0`, an annotated tag whose object is `69c8159` and whose commit is
`2add129e65d04759ce67c77520208b854c05dcee`.

**Package digest, read from the Hex API rather than from a terminal:**

    $ curl -s https://hex.pm/api/packages/beam_mcp/releases/0.1.0 | jq '{checksum, inserted_at, has_docs}'
      checksum:     b8c351933260d90844eae1614ae4759cf979d4a524ee139fbbef1c2dfaab5e7f
      inserted_at:  2026-09-06T20:57:51.749883Z
      has_docs:     true
      requirements: ["jason"]

The registry's own value is the one recorded, because a checksum printed by the machine that
built the tarball attests to that machine and not to what a consumer will fetch.

### Why 0.1.0 was not published at `c5da02f`

The extraction was complete and the gate was green, and the package was still not fit to
publish. A revision check found the reason:

> **a `2026-07-28` request answered with a `2024-11-05`-shaped result that looks like success.**

A client speaking the current revision sent `tools/list` carrying its version and capabilities
in `_meta`, exactly as that revision requires, and got back a well-formed result — with no
`resultType`, no `_meta` `serverInfo`, and none of the fields the revision mandates. Not an
error a client could act on. A wrong answer wearing the shape of a right one.

The specification names this case itself: a modern client against a legacy server may be
rejected, met with silence, *"or even process an era-ambiguous method under legacy semantics."*
Publishing that under a name as general as `beam_mcp` would have put a library on Hex that
fails quietly against the revision most evaluators would try first.

### Added

- The MCP protocol core as a standalone package: `BeamMCP.Server`,
  `BeamMCP.Transport.Stdio`, `BeamMCP.Schema`, `BeamMCP.ToolSpec` (`083838e`).
- `BeamMCP.ToolCatalog`, a behaviour, and a published dispatch callback type. Injection
  without a specification is a claim with nothing behind it (`083838e`).
- `:input_schema` on `ToolSpec`. The catalog supplies a tool's schema, `tools/list` advertises
  it and `tools/call` enforces the same one (`c5da02f`).
- **Dual-era protocol support: `2026-07-28` and `2025-11-25`.** `server/discover`, per-request
  `_meta` version handling, `resultType` and `_meta` `serverInfo` on modern results, and
  `UnsupportedProtocolVersionError` (`-32022`) listing the supported set.
- A quality gate (`tools/gate.sh`) and CI, with no ratchet baseline (`ee63228`).
- Transport tests, with coverage demonstrated by mutation (`13a6238`).
- `README.md`, `CONVENTIONS.md`.

### Changed

- The tool-name check routes through the injected catalog. Previously `tools/list` honoured
  the injected catalog while `tools/call` consulted a hardcoded one, so a tool could be
  advertised and then refused (`083838e`).
- `:dispatch` and `:tool_catalog` are injected; `:tool_catalog` is required (`083838e`).
- The advertised server name is a `:server_name` option defaulting to `beam_mcp` (`083838e`),
  and the advertised version is read from the project config rather than restated in the
  source (`1ac057e`).
- Argument keys are derived from the tool's schema; values pass through unchanged, since
  coercing a string to a domain term belongs to the host (`c5da02f`).

### Fixed

- **Error payloads no longer carry `inspect/1` output.** A failed call returned Elixir term
  syntax — a map literal and a bare atom — to a client with no way to parse it and no reason
  to know the server's language. `structuredContent` now carries the error as a JSON object
  and `content` carries a sentence.

### Removed

- Per-tool `input_schema/1` clauses, `input_schema_for/1`, the hardcoded argument-key
  allowlist and the domain value coercion — one consumer's domain data in a generic module
  (`c5da02f`).
- **`2024-11-05` is no longer supported.** A client requesting it receives `-32022`.
- JSON-RPC batching is refused. It was added in `2025-03-26` and removed in `2025-06-18`, so
  it is required by exactly one revision of five and by neither of the two supported here.
- `ping` at the modern era. It was removed in `2026-07-28`; the legacy era still answers it.

### Not adopted, deliberately

Three optional items from `2025-11-25`, recorded so their absence is not read as an oversight:

- **JSON Schema 2020-12 dialect declaration.** `BeamMCP.Schema` is a deliberately small
  subset — `type`, `properties`, `required`, `additionalProperties`, bounds. Declaring a
  dialect it does not fully implement would claim more than it does.
- **`title` on tools.** Optional human-readable display name. Nothing in the package needs it,
  and a catalog that wants one can carry it when the field is supported end to end.
- **`icons` on tools.** Optional metadata, no consumer.

Each is additive and can be adopted without a breaking change.

### Known gaps

- CI has not run against this history at the time of writing; a committed workflow is not a
  working one until a run exists.
- Streamable HTTP and the rest of the non-stdio surface (see below).
- Streamable HTTP, `subscriptions/listen`, MRTR, tasks, authorization, elicitation, sampling
  and roots are not implemented. This is a stdio, tools-only server.
