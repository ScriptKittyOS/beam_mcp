From: beam_mcp · Reviewer lane r1
To: beam_mcp · Coding Agent
Re: slice 002-streamable-http, round 1, correctness and conformance
Type: Report

Tree read: `babfc5e40522288e49fb17475bab1765e83711fb`
(`cd /home/aylac/Projects/beam_mcp-wt/002-review1 && git write-tree`; also written to
`/home/aylac/Projects/beam_mcp-wt/002-review1/logs-r1.tree`)

Scope: `lib/`, `test/`, `README.md`, `CHANGELOG.md`, `mix.exs`. All probes and mutations were run
against a copy at
`/tmp/claude-1000/-home-aylac-Projects-hacktui-hermes/775c8d71-6ac1-4653-8798-382001e76089/scratchpad/r1b/mut`,
never the review worktree; `diff -r --brief lib <review>/lib` was re-run after every mutation and
reports IDENTICAL.

---

## 1. BLOCKING — `0.3.0` does not compile for any consumer that does not itself depend on `plug`

**file:line** `lib/beam_mcp/transport/http.ex:49-51`; `mix.exs:36-37`; claims at `README.md:97`
and `CHANGELOG.md:21`.

`plug` is `optional: true`, so Mix does not install it into a consumer's tree. But
`lib/beam_mcp/transport/http.ex` is unconditionally compiled and does `import Plug.Conn` at
module level, which is a hard compile error when `Plug.Conn` is absent (`@behaviour Plug` alone
would only warn; the `import` will not).

**Expected**: a stdio-only host adds `{:beam_mcp, "~> 0.3.0"}` and it compiles — this is exactly
what `README.md:97` ("`plug` and `bandit` are optional dependencies; a stdio-only host does not
pull them in") and `CHANGELOG.md:21` promise, and both ship in the Hex tarball.

**Observed**: hard `CompileError`. Every existing `0.2.0` stdio consumer breaks on upgrade.

```
$ cat consumer/mix.exs   # deps: [{:beam_mcp, path: "<the reviewed tree>"}]
$ cd consumer && mix deps.get && mix compile
==> jason
Compiling 10 files (.ex)
Generated jason app
==> beam_mcp
Compiling 6 files (.ex)
    error: module Plug.Conn is not loaded and could not be found
    │
 51 │   import Plug.Conn
    │   ^
    │
    └─ lib/beam_mcp/transport/http.ex:51:3: BeamMCP.Transport.HTTP (module)

== Compilation error in file lib/beam_mcp/transport/http.ex ==
** (CompileError) lib/beam_mcp/transport/http.ex: cannot compile module BeamMCP.Transport.HTTP
```

`optional: true` controls *resolution*, not *compilation*. The module body must be guarded —
`if Code.ensure_loaded?(Plug) do … end` around the `defmodule`, or equivalent — and the guard
needs a check that actually builds the package with `plug` absent, because nothing in the current
suite can fail on this: `plug` is always present in this project's own dev/test tree.

Note this is also a **false README claim in the shipped tarball**, and the `readme_claims_test`
mechanism did not catch it: the new HTTP claims were not added to its list, and its own moduledoc
(`test/beam_mcp/readme_claims_test.exs:9-14`) says it does not catch a claim added without a test.

---

## 2. BLOCKING — `Mcp-Method` and `Mcp-Name` are neither required nor validated; the CHANGELOG claims otherwise

**file:line** `lib/beam_mcp/transport/http.ex:210-251` (`check_protocol_header/2` is the only
header validation in the module); doc claim at `CHANGELOG.md:44-52`.

**Spec** (`slices/002-streamable-http/logs/spec-streamable-http.md:288-294`, confirmed against the
live page):

> | `Mcp-Method` | `method` | All requests |
> | `Mcp-Name` | `params.name` or `params.uri` | `tools/call`, `resources/read`, `prompts/get` requests |
> These headers are **REQUIRED** for compliance.

and (`spec-streamable-http.md:583-600, 620-628`):

> Servers that process the request body **MUST** reject requests where the values specified in
> the headers do not match the corresponding values in the request body. This prevents potential
> security vulnerabilities when different components in the network rely on different sources of
> truth (e.g., a load balancer routing on the header value while the MCP server executes based on
> the body value).
> … servers **MUST** return HTTP status `400 Bad Request` and **MUST** include a JSON-RPC error
> response using … `-32020` … Validation failure conditions include: A required standard header
> (`MCP-Protocol-Version`, `Mcp-Method`, `Mcp-Name`) is missing.

This server processes the request body, so both MUSTs bind it.

**Expected**: (A) a POST with no `Mcp-Method` → `400` / `-32020`. (B) a POST whose `Mcp-Method`
and `Mcp-Name` contradict the body → `400` / `-32020`, and dispatch is not reached.

**Observed**: both accepted and executed.

```
$ MIX_ENV=test mix run probe_headers.exs
A observed: status=200 body={"id":1,...,"result":{...,"tools":[...]}}
B observed: status=200 body={"id":1,...,"result":{...,"content":[{"text":"{}","type":"text"}],"isError":false,...}}
B dispatch reached: {:dispatched, :echo}
```

Case B is the exact scenario the spec names: headers said `Mcp-Method: tools/list` /
`Mcp-Name: not_echo`, the body said `tools/call` / `echo`, and the server ran `echo`. An
intermediary routing or rate-limiting on the mirrored headers is authorising a different call from
the one executed. For a transport whose stated design principle is "a Plug that serves
`tools/call` to anyone who can reach the port is a confused-deputy surface"
(`http.ex:15-17`), this is the same class of defect one layer up.

Separately, `CHANGELOG.md:44` introduces its table as "**What the transport enforces**, each a MUST
of the transport specification". The table omits the two REQUIRED headers entirely, so a consumer
reading the shipped changelog is told the transport's MUST coverage is complete when it is not.

---

## 3. BLOCKING — an unimplemented RPC method answers `200`; the spec requires `404` with `-32601`

**file:line** `lib/beam_mcp/transport/http.ex:285-288`.

**Spec** (`spec-streamable-http.md:271-275`, confirmed live):

> If the server does not implement the requested RPC method, it **MUST** respond with
> `404 Not Found` and a JSON-RPC error with code `-32601` (`Method not found`). The JSON-RPC error
> body distinguishes this case from a `404` returned by a legacy HTTP+SSE server…

`do_dispatch/3` maps any non-`nil` response to `200`, so the `-32601` that
`lib/beam_mcp/server.ex:234-236` already produces never reaches the wire with the right status.

**Observed**:

```
C observed: status=200 body={"error":{"code":-32601,"message":"Method not found: resources/list"},"id":1,"jsonrpc":"2.0"}
```

**Expected**: `404` with that same body. This is load-bearing for interop, not cosmetic: the
Backward Compatibility section (`spec-streamable-http.md:645-660`) has clients switch on
`400/404/405` + body shape to decide whether to fall back to the legacy transport. A modern
`-32601` returned as `200` is invisible to that algorithm.

---

## 4. MEDIUM — a missing `MCP-Protocol-Version` is answered `-32600`; the spec requires `-32020`

**file:line** `lib/beam_mcp/transport/http.ex:216-222`; the test that pins it,
`test/beam_mcp/transport/http_test.exs:111-116`, asserts only the status and the message string,
so it cannot notice.

**Spec**: a missing `MCP-Protocol-Version` is listed under *Validation failure conditions*
(`spec-streamable-http.md:620-622`), and those MUST use `-32020` (`:596-602`).

**Observed**:

```
MISSING-HEADER status=400 body={"error":{"code":-32600,"message":"Missing mcp-protocol-version header; it is required on every POST to this endpoint"},"id":7,"jsonrpc":"2.0"}
```

The status is right; the code is not. A conforming client keys off `HeaderMismatch` to re-derive
its headers and retry (`spec-streamable-http.md:541-546`); `-32600` gives it nothing to key off.
The module already gets this right for the *mismatch* case one branch below, which makes the
inconsistency more likely to be an oversight than a decision.

---

## 5. MEDIUM — the `403` body reflects the host's `authorize` failure term back to an unauthenticated caller

**file:line** `lib/beam_mcp/transport/http.ex:132-133`:

```elixir
{:error, reason} ->
  send_json(conn, 403, error(nil, -32_600, "Forbidden: #{inspect(reason)}"))
```

The module states the opposite policy 130 lines later, for the crash path
(`http.ex:261-264`): "answer with a JSON-RPC internal error carrying NO detail… Leaking
`Exception.message/1` to an HTTP caller would hand an unauthenticated party the host's internals."
`CHANGELOG.md:80` ships that as a headline. The same argument applies here and more strongly: the
`authorize` reason is produced by the host's identity code, at the one point in the request where
the caller is known *not* to be authorised.

**Observed** (host returns `{:error, {:bad_token, "db-conn-string://user:p4ssw0rd@internal-host/db"}}`):

```
authorize refusal: status=403 body={"error":{"code":-32600,"message":"Forbidden: {:bad_token, \"db-conn-string://user:p4ssw0rd@internal-host/db\"}"},"id":null,"jsonrpc":"2.0"}
```

**Expected**: a fixed `"Forbidden"`, with `reason` going to `Logger` as the crash path does.
The package documents that it "never inspects what [authorize] does" (`http.ex:23`) — it should
not serialise it to the network either.

---

## 6. MEDIUM — the 1 MiB body cap and the 413 keep-alive fix have **no test**; three mutations survive, and the CHANGELOG's measurement does not reproduce

**file:line** `lib/beam_mcp/transport/http.ex:61-64, 164-186`; claims at `CHANGELOG.md:83-87`.

Mutation scoring. Every mutant was applied with an asserted before/after count, compiled with
`mix compile --force` (a `mv`-based restore preserves mtimes and silently leaves a stale mutant in
`_build` — this bit me mid-review and every result below was re-derived after a forced rebuild),
and each survivor is additionally proven **by effect** against a real Bandit listener on
`127.0.0.1:4599`.

| mutant | applied | suite | verdict |
|---|---|---|---|
| M11 `413,` → `200,` | old 1→0, new 1 | 71 tests, 0 failures | **SURVIVOR** |
| M12 `read_body(conn, length: @max_body_bytes)` → `read_body(conn)` | old 1→0, new 1 | 71 tests, 0 failures | **SURVIVOR** |
| M6 drop `put_resp_header("connection", "close")` | occurrences 1→0 | 71 tests, 0 failures | **SURVIVOR** |

Effect proof for M11 — the live server answered an oversized body `200 OK` while the suite stayed
green:

```
APPLIED: old '413,' count now 0 ; new '200,' count now 1
--- effect proof: real Bandit, oversized body under the mutant ---
6 oversized (413)      : HTTP/1.1 200 OK
--- suite under the mutant ---
71 tests, 0 failures
```

Effect proof for M6, which also raises a second point:

```
APPLIED: 'connection, close' occurrences now 0
6 oversized (413)      : HTTP/1.1 413 Request Entity Too Large
7 next after 413       : HTTP/1.1 200 OK
--- suite under the mutant ---
71 tests, 0 failures
```

Two things follow. First, the whole oversized-body path — cap, status, and the connection close —
is unpinned; `slices/002-streamable-http/logs/resilience.txt` *demonstrates* it but nothing
*guards* it, which is the distinction the project's own
`test/beam_mcp/readme_claims_test.exs:87-90` insists on for the `files:` change.

Second, I could not reproduce the failure `CHANGELOG.md:83-85` says motivated the fix ("Measured:
`413`, then a **timeout**, then a success"). With `connection: close` removed, the request after the
413 returned `200 OK` immediately on the same socket (row 7 above); with it present, that request
fails `:closed`. So on this measurement the header is not recovering a broken connection — it is
tearing down one that worked. I am not asserting the original measurement was wrong; my client is a
raw `:gen_tcp` socket sending a 1.2 MB body in one write, which may differ from theirs. But a
behavioural claim in a shipped `CHANGELOG.md` that a reviewer cannot reproduce needs either the
reproducing command archived beside it or the claim narrowed.

---

## 7. LOW — `ttlMs`/`cacheScope` are pinned only through the HTTP transport, and the "both eras" decision is untested

**file:line** `lib/beam_mcp/server.ex:183-195`; tests, or their absence, in
`test/beam_mcp/server_test.exs`.

```
$ grep -rn "ttlMs\|cacheScope\|tools_ttl\|tools_cache" test/ | grep -v transport/http_test
(no output)
```

Killing M17 (`"ttlMs"` → `"ttlMsX"`) fails only `BeamMCP.Transport.HTTPTest`. SCR-261 is a change to
`Server.handle_message/2`, reachable from stdio as well, and nothing in `server_test.exs` or
`negotiation_test.exs` asserts it. If the transport were removed tomorrow the requirement would be
silently unpinned; and the fields are, today, unasserted on the stdio path that is this package's
primary transport.

In particular the design decision the comment at `server.ex:185-188` defends — emitting at *both*
eras — has no test. **The claim itself checks out**, so this is coverage, not a defect:

* `slices/.../logs/spec-legacy-basic.md:73` — "The `result` **MAY** follow any JSON object
  structure." Emitting extra keys at `2025-11-25` is permitted.
* Behaviour confirmed: `legacy 2025-11-25 tools/list result: %{"cacheScope" => "private",
  "tools" => [], "ttlMs" => 0}` and the same for a bare no-`_meta` request.

---

## 8. LOW — `init/1` validates two options and not `:tool_catalog`, which `Server.new/1` `fetch!`es

**file:line** `lib/beam_mcp/transport/http.ex:70-114`.

The stated contract is "a host that omits either gets an `ArgumentError` **when the Plug is
initialised**, not on the first request" (`http.ex:19-20`), and `http_test.exs:80-84` names it
"the failure is at init, not at request time". `:tool_catalog` is equally undefaultable —
`server.ex:87` does `Keyword.fetch!` — but is not checked at init:

```
init returned: [:authorize, :allowed_origins, :server_opts] -- no raise
first request: status=500 body={"error":{"code":-32603,"message":"Internal error"},"id":1,"jsonrpc":"2.0"}
```

A host that misspells `tool_catalog:` starts clean and 500s on every request, with the rescue at
`http.ex:267-272` swallowing the `KeyError` that would have named the cause. One `Keyword.has_key?`
in `init/1` closes it.

---

## 9. LOW — the `405` carries no `Allow` header

**file:line** `lib/beam_mcp/transport/http.ex:160-162`.

RFC 9110 §15.5.6: "The origin server MUST generate an `Allow` header field in a 405 response
containing a list of the target resource's currently supported methods."

```
405 resp_headers=[{"cache-control", "max-age=0, private, must-revalidate"}, {"content-type", "application/json; charset=utf-8"}]
```

`Allow: POST` is one line. (The 405-for-GET/DELETE behaviour itself is right — see verified items.)

---

## 10. LOW — `CHANGELOG.md:44` calls "POST only → 405" a MUST of the transport specification

The spec makes *supporting POST* a server MUST (`spec-streamable-http.md:45-47`) and makes
`405` for GET/DELETE a **SHOULD**, in Backward Compatibility (`:676-681`). The row is good
behaviour described with the wrong modal in a document that ships to consumers.

---

## Verified, no finding

* **The archive is faithful.** I re-fetched
  `https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http` and
  compared it to `slices/002-streamable-http/logs/spec-streamable-http.md`. Every normative passage
  I relied on (Security & Endpoint, Sending Messages, Protocol Version Header, Standard Request
  Headers, Server Validation, Backward Compatibility) matches the archive.
* **Acceptance criterion 6 is met.** `handle_message/2` has **13 clauses at `bee3d26` and 13 at
  `babfc5e`**; `lib/beam_mcp/server.ex` has exactly **3 hunks** — the `@type state()` fields,
  `new/1`, and the `tools/list` clause. No other clause is touched.
  (`git show <ref>:lib/beam_mcp/server.ex | grep -c "^  def handle_message"`;
  `git diff … -- lib/beam_mcp/server.ex | grep -c "^@@"`.)
* **The cacheable-fields requirement is complete for this package.** `spec-changelog.md:38` requires
  the fields on `tools/list`, `prompts/list`, `resources/list`, `resources/read`,
  `resources/templates/list`; only `tools/list` exists here.
* **The remaining protocol behaviour is genuinely tested.** Killed with an asserted application
  count and a forced rebuild: origin rejection (M1c), non-POST refusal (M13), missing-header
  refusal (M3b), `-32020` (M4), `-32022` (M5), `authorize` being called at all (M8), `202` for
  notifications (M9), no exception detail in the `500` (M10), non-permissive `cacheScope` default
  (M14), `ttlMs` default (M15), host-supplied `ttlMs` reaching the result (M16), and both field
  names (M17, M18).
* **Answering an error on the pre-`read_body` `conn`** — the `with`'s `else` branch uses the outer
  `conn`, not the one `read_body_bounded/1` returned. Measured against real Bandit over one
  keep-alive socket: ok `200`, HeaderMismatch `400`, ok `200`, bad-JSON `400`, ok `200`. No stale
  adapter-state problem.
* **Legacy-era mechanisms are correctly ignored** — `Mcp-Session-Id` and `Last-Event-ID` are never
  read; GET/DELETE/PUT/HEAD/OPTIONS/PATCH all get `405`, which is what
  `spec-streamable-http.md:676-681` asks of a server that supports only this revision.
* **The gate passes, read line by line, not by exit code**:
  `format pass · compile pass · test pass · credo pass · reuse pass (22 commentable files) ·
  licence files pass · Gate OK.` — `71 tests, 0 failures`.

## Filed, not blocking (records)

* `test/beam_mcp/readme_claims_test.exs:87` says "no release of this package before **0.2.1**
  contained it", but the release adding `CHANGELOG.md` to `files:` is `0.3.0`.
* `mix.exs:22` `docs: [extras: ["README.md"]]` — `CHANGELOG.md` now ships in the tarball but is not
  in the generated docs.

---

VERDICT: changes required
