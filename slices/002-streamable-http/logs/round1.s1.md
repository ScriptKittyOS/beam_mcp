<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

From: beam_mcp · Security lane s1
To: beam_mcp · Coding Agent
Re: slice 002-streamable-http, round 1, HTTP attack surface
Type: Report

**Tree reviewed:** `babfc5e40522288e49fb17475bab1765e83711fb`
(`git write-tree` in `/home/aylac/Projects/beam_mcp-wt/002-review1`, also written to
`logs-s1.tree` in that checkout).

**Method.** Everything below was measured against a real `Bandit` listener on `127.0.0.1`
high ports, driven with a raw `:gen_tcp` client so the exact bytes on the wire — duplicate
headers, lying `Content-Length`, dribbled bodies, a malformed request line — are mine and not
a client library's. `mix test` on this tree: **71 tests, 0 failures.** Harness scripts are in
my scratchpad; every finding below quotes the request and the response.

**The headline: the contract holds. I could not evade it.** Section 1 of the PLAN is correct
as built — see "Attacks that failed", which is the longer half of this report. What I did find
is that the package's *stated* discipline about not leaking host internals to an HTTP caller is
enforced on one branch and not on the two next to it.

---

## 1. BLOCKING — the host's authorization failure reason is `inspect`ed into the 403 body, to an unauthenticated caller

`lib/beam_mcp/transport/http.ex:133`

```elixir
{:error, reason} ->
  send_json(conn, 403, error(nil, -32_600, "Forbidden: #{inspect(reason)}"))
```

`:authorize` is documented as `(Plug.Conn.t() -> :ok | {:error, term()})` and the package
"never inspects what it does" (moduledoc, line 24). It does inspect it — literally — and puts
the result in a response body that is returned to a caller who has just been told they are not
allowed to talk to this endpoint. `{:error, term()}` invites a structured term, and a host
building one naturally puts the reason for the refusal in it.

Host used (a plausible one, not a contrived one):

```elixir
authorize: fn _ ->
  {:error, %{expected_bearer: "s3cr3t-token-abc",
             db: "postgres://user:pw@10.0.0.5/prod"}}
end
```

Request:

```
POST /mcp HTTP/1.1
Host: 127.0.0.1
Content-Type: application/json
MCP-Protocol-Version: 2026-07-28
Content-Length: 86

{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"echo","arguments":{}}}
```

Response:

```
HTTP/1.1 403 Forbidden
{"error":{"code":-32600,"message":"Forbidden: %{expected_bearer: \"s3cr3t-token-abc\", db: \"postgres://user:pw@10.0.0.5/prod\"}"},"id":null,"jsonrpc":"2.0"}
```

**What an attacker gains:** whatever the host put in its refusal term, before authenticating.
An `{:error, exception}` from a `rescue` in the host's auth path would ship a struct with a
message; an `{:error, {:expired, %User{...}}}` ships a user record; an
`{:error, {:no_match, conn.req_headers}}` ships the request back plus anything the host added.

This is the same class the module refuses on the crash path, and says so at length
(`http.ex:255-264`: *"Leaking `Exception.message/1` to an HTTP caller would hand an
unauthenticated party the host's internals"*). The crash path is at least **behind** authorize.
This one **is** the unauthenticated path. The rule is applied to the safer branch and not the
more exposed one.

The test suite does not see it because `http_test.exs:88` refuses with the atom `:nope`, whose
`inspect` discloses nothing.

**Fix shape (yours to choose):** send a fixed `"Forbidden"` and `Logger`-log the reason, exactly
as the crash path already does. If a host wants a reason on the wire it can build the response
itself; it cannot un-send one this Plug decided to include.

---

## 2. BLOCKING — a non-map `_meta` crashes *outside* the rescue: bare, empty HTTP 500

`lib/beam_mcp/transport/http.ex:212` (`check_protocol_header/2`), reached from `call/2:123`,
which is **not** inside the `rescue` at `http.ex:267`.

```elixir
body_version = get_in(message, ["_meta", @version_meta_key])
```

`decode/1` guarantees only that the body is a JSON **object**. `_meta` is then any JSON value.

Request (63 bytes):

```
POST /mcp HTTP/1.1
Content-Type: application/json
MCP-Protocol-Version: 2026-07-28

{"jsonrpc":"2.0","id":1,"method":"ping","_meta":"x"}
```

Response:

```
HTTP/1.1 500 Internal Server Error
<empty body>
```

Server log:

```
** (FunctionClauseError) no function clause matching in Access.get/3
    (elixir 1.19.2) lib/access.ex:324: Access.get("x", "io.modelcontextprotocol/protocolVersion", nil)
    (beam_mcp 0.3.0) lib/beam_mcp/transport/http.ex:212: BeamMCP.Transport.HTTP.check_protocol_header/2
    (beam_mcp 0.3.0) lib/beam_mcp/transport/http.ex:123: BeamMCP.Transport.HTTP.call/2
```

Also reproduced with `"_meta":[1,2]` (`ArgumentError`, "the Access module supports only keyword
lists") and `"_meta":7` (`FunctionClauseError`). All three: `500`, empty body.

**What an attacker gains:** the empty 500 that `http_test.exs:221` — *"answers with a JSON-RPC
internal error, not an empty 500"* — asserts is gone. It is not gone; it is one JSON scalar
away, and it is reachable with a smaller, cheaper request than the dispatch crash that test
covers. Concretely: (a) the transport's "every refusal is a JSON-RPC error" property is false,
so a conforming client gets an unparseable response; (b) an unhandled exception escapes the
Plug into the host's error handling, and a host that wraps this Plug in `Plug.Debugger` for dev
— an extremely common thing to do — renders the stacktrace, the source line, and the request
into the response body, which is precisely the disclosure `http.ex:255-264` set out to prevent;
(c) it is a free, unattributed log-flood primitive, a full formatted stacktrace per 63-byte
request.

Note the sibling: `do_dispatch/3:282` does `Map.put(message["_meta"] || %{}, ...)`, which
`BadMapError`s on the same input. That one *is* inside the rescue, so fixing only line 212
converts this to a `-32603`. The right answer is to reject a non-map `_meta` as a `400`
malformed request in `decode/1` or at the top of `check_protocol_header/2`, since a `_meta`
that is not an object is not a valid MCP message.

---

## 3. NON-BLOCKING — `rescue` catches raises only; `exit` and `throw` from the host's dispatch produce the empty 500 the slice says it removed

`lib/beam_mcp/transport/http.ex:265-272`

```elixir
defp dispatch(conn, message, opts) do
  do_dispatch(conn, message, opts)
rescue
  exception -> ...
end
```

`rescue` handles `:error`-class exceptions. It does not handle `:exit` or `:throw`. Measured
against one listener, three dispatch functions:

| dispatch does | HTTP status | body |
|---|---|---|
| `raise "..."` | 500 | `{"error":{"code":-32603,"message":"Internal error"},"id":1,...}` |
| `exit(:kaboom_secret_exit)` | 500 | *(empty)* |
| `throw(:thrown_secret)` | 500 | *(empty)* |
| returns `{:ok, %{p: self()}}` (unencodable) | 500 | `{"error":{"code":-32603,...}}` — correctly caught |

`exit` is not an exotic failure in a BEAM host: `GenServer.call/3` on a timeout or a dead
process **exits**, `Task.await/2` on a timeout **exits**, `:sys.get_state` on a busy process
**exits**. A host whose `dispatch` calls into a GenServer — which is the shape the README
recommends — will hit the empty-500 branch on its first backend timeout, in production, having
tested only the `raise` case because that is the case the package documents and tests
(`http_test.exs:221`, `logs/resilience.txt` line "dispatch RAISES").

`logs/resilience.txt` records only the raising variant, so the resilience table overstates what
was measured. `catch :exit, reason` / `catch value` alongside the `rescue`, and a row per class
in the log, closes it.

---

## 4. NON-BLOCKING — only the *first* `Origin` header is validated

`lib/beam_mcp/transport/http.ex:145-155`

```elixir
[origin | _] when is_binary(origin) ->
  if origin in allowed, do: :ok, else: {:error, 403, ...}
```

The spec MUST quoted at `logs/spec-streamable-http.md:57-61` is *"If the `Origin` header is
present and invalid, servers MUST respond with HTTP 403 Forbidden."* With two `Origin` headers,
an invalid one is present and the request is served.

```
POST /mcp HTTP/1.1
Origin: https://app.example.com
Origin: https://evil.com
MCP-Protocol-Version: 2026-07-28
...
```
→ `HTTP/1.1 200 OK`, `tools/call` executed.

Reversed order (`evil` first) → `403`, so it is order-dependent, not a general bypass.

**What an attacker gains:** in the direct browser case, nothing — a browser emits exactly one
`Origin` and cannot be made to emit two. The exposure is an intermediary that merges, reorders
or appends `Origin` (some proxies and service meshes do), and any host that terminates TLS in
front of this Plug. The fix is one line: validate every value, not the head —
`Enum.all?(get_req_header(conn, "origin"), &(&1 in allowed))`, with `[]` still passing.

---

## 5. NON-BLOCKING — a body-reading `:authorize` works for small requests and silently returns nothing for large ones

`lib/beam_mcp/transport/http.ex:120-121` — `opts.authorize.(conn)` runs **before**
`read_body_bounded(conn)`.

`:authorize` is the package's whole answer to the confused-deputy problem, and the problem it
names is `tools/call` specifically. The obvious host implementation is therefore per-tool: read
the body, look at `params.name`, decide. That host gets a size-dependent endpoint. Same
listener, same `authorize` (reads the body with `Plug.Conn.read_body/2`, returns `:ok`), three
body sizes:

```
body     93 bytes -> HTTP/1.1 200 OK   (correct result)
body  99972 bytes -> <no response, connection closed>
body 899972 bytes -> <no response, connection closed>
```

The small case passes because the whole body arrived in the adapter's first read; the large
cases do not, and the transport's own `read_body` then has nothing to read. A host writes this,
tests it with a small fixture, and ships an endpoint that fails on real payloads.

**What an attacker gains:** a cheap, reliable request-killer against such a host (send >100 KB),
and — worse for the host — whatever their per-tool policy was supposed to do, it now does not
run to completion on exactly the requests large enough to matter.

Not a bug in the bytes so much as a hole in the contract: nothing tells a host whether
`authorize` may read the body, and the one thing `authorize` most needs to see is the one thing
it cannot reliably see. Either decode first and pass the message to `authorize` alongside the
conn, or state in the `@doc` that `authorize` must not read the body and that per-tool policy
belongs in the host's `dispatch`.

---

## 6. NOTE — the Plug answers on every path

`lib/beam_mcp/transport/http.ex` has no path check, and the documented wiring
(moduledoc:34-42, `README.md:100-110`) hands the module straight to `Bandit`, which mounts it at
the root. Measured: `POST /`, `POST /anything/else` → `200 OK` with the tool result. The spec
(`logs/spec-streamable-http.md:47-49`) says the server **MUST** provide *a single* HTTP endpoint
path. Low security weight — a scanner finds the endpoint slightly more easily — but the
documented usage does not produce the endpoint shape the module's own first line claims
("a `Plug` serving `2026-07-28` at one endpoint").

Adjacent conformance gap, same area: the spec at `logs/spec-streamable-http.md:266-270` requires
`404` + `-32601` for an unimplemented RPC method; this returns `200` with the `-32601` body.

## 7. NOTE — `:authorize` returning anything other than `:ok` / `{:error, _}` is an empty 500

`authorize: fn _ -> false end` → `WithClauseError` at `http.ex:118`, uncaught, `HTTP 500`, empty
body. Fails **closed**, which is the right direction, but it is the same unparseable response as
finding 2 and it is a host mistake the Plug could name.

## 8. NOTE — the 413 is not delivered above ~4 MiB

Body cap itself is exact and correct: `1_048_576` bytes → served; `1_048_577` → `413`. But:

```
body  1100008 -> 413 Request Entity Too Large
body  2000008 -> 413
body  4000008 -> 413
body  8000008 -> no response (connection reset)
body 16000008 -> no response (connection reset)
```

The server closes the connection before the client has finished writing, and the pending
response is lost to the reset. Bandit-level, no resource is retained, and the refusal still
happens — but a caller cannot distinguish "too large" from "server gone".

## 9. NOTE — `Jason` resolves duplicate JSON keys to the **first** value

`Jason.decode!(~s({"method":"ping","method":"tools/list"}))` → `%{"method" => "ping"}`.
Confirmed end-to-end: that body is executed as `ping`, not `tools/list`. Python's `json`,
Node's `JSON.parse` and most WAF body parsers keep the **last**. Any host that filters MCP
methods at a gateway in front of this Plug is desynchronised from what this server executes.
Nothing for the package to fix in code; worth one sentence to hosts who plan to filter upstream.

## 10. NOTE — over HTTP, `tools/call` executes with no `initialize`, ever

`state.initialized?` is written at `server.ex:130` and `server.ex:175` and **read nowhere**
(`grep -n "initialized?" lib/`: four hits, all writes or the typespec). The transport builds a
fresh `Server.new/1` per request (`http.ex:285`), so every HTTP request runs with
`initialized?: false` and `tools/call` dispatches regardless.

The README says (line 128-131) *"a request with no era established is malformed and refused."*
That is **true of the era** — see the failed attacks below, I could not get a non-modern or
absent era past the header check — and **not true of the lifecycle**. The PLAN's §1 framing
("the bare-request path that exists on stdio cannot exist over conformant HTTP") is half right
in the same way. Pre-existing core behaviour, surfaced rather than caused by this slice; I raise
it because §1 is the claim under review and this is the part of it that does not hold.

## 11. NOTE — "at start, not on the first request" holds for the default init mode only

`use Plug.Builder, init_mode: :runtime` + `plug BeamMCP.Transport.HTTP` **compiles**; the
`ArgumentError` then fires on the first request instead. Still fails closed, still refuses. Only
the timing claim is mode-dependent.

---

## Attacks that failed — the contract held on every path I tried

I could not break §1's central claim, and this list is the evidence for that.

**Evading the two required options.** All of the following raise
`ArgumentError` naming the missing option:

| wiring | result |
|---|---|
| `HTTP.init([])` | ArgumentError (`:authorize`) |
| `HTTP.init(tool_catalog: Cat)` | ArgumentError |
| `HTTP.init(tool_catalog: Cat, authorize: fn _ -> :ok end)` | ArgumentError (`:allowed_origins`) |
| `HTTP.init(tool_catalog: Cat, allowed_origins: :any)` | ArgumentError (`:authorize`) |
| `HTTP.init(authorize: nil, allowed_origins: nil)` | ArgumentError |
| `HTTP.init(%{authorize: ..., allowed_origins: ...})` (map, not keyword) | `FunctionClauseError` in `Keyword.get/3` — fails |
| `Bandit.start_link(plug: BeamMCP.Transport.HTTP)` (bare module) | ArgumentError at start; nothing binds the port (`:econnrefused`) |
| `use Plug.Builder; plug BeamMCP.Transport.HTTP` | ArgumentError at **compile** time |
| `use Plug.Router; forward "/mcp", to: BeamMCP.Transport.HTTP` (no `init_opts`) | ArgumentError at **compile** time |
| `use Plug.Builder, init_mode: :runtime; plug ...` | compiles; ArgumentError on first request (finding 11) |
| `[authorize: fn, authorize: nil, ...]` duplicate keys | first wins → accepted, and `[authorize: nil, authorize: fn]` → raises. Both directions fail safe. |

`allowed_origins: []` is accepted, which is correct: it rejects every present `Origin` and is
fail-closed. `authorize: &IO.inspect/1` is accepted — any 1-arity function is — but a return
value that is not `:ok` refuses the request (finding 7).

**Reaching `state.dispatch` without passing `authorize`.** No path found. `dispatch/3` is called
from exactly one place, `call/2:124`, after `opts.authorize.(conn)` at line 120. I also checked
the side doors into the core: an **id-less** `tools/call` does not match `server.ex:197`, falls
to the `_message` catch-all at `server.ex:242`, and returns `202` with **no** dispatch; a JSON
array body is refused at `http.ex:196` before the core's batch clause is reached.

**Forging or omitting the era.** Every attempt refused:

| request | response |
|---|---|
| no `MCP-Protocol-Version` header | `400` `-32600` "Missing mcp-protocol-version header" |
| header `1999-01-01` | `400` `-32022` `{"supported":["2026-07-28"],"requested":"1999-01-01"}` |
| header modern, `_meta` claims `2025-11-25` | `400` `-32020` HeaderMismatch |
| two headers, bad first | `400` `-32022` (first wins, and it is the strict direction) |
| two headers, good first | `200` — first wins here too; the second is ignored, not honoured |

`do_dispatch/3:278-283` overwrites `_meta` with the modern version unconditionally, so no
message carrying a legacy era or no era reaches `handle_message/2`. That half of §1 is sound.

**Origin bypass.** Against `allowed_origins: ["https://app.example.com"]`, every one of these
got `403 Origin not allowed`: `https://evil.com`, `HTTPS://APP.EXAMPLE.COM` (case),
`https://app.example.com/` (trailing slash), `https://app.example.com ` (trailing space),
`https://app.example.com\t` (trailing tab), `null`. Comparison is exact string membership with
no prefix, suffix or normalisation logic — the usual origin-check bug class is simply absent.
Absent `Origin` passes, which matches the quoted MUST and is documented at `http.ex:141-142`.
Browser CSRF is additionally blocked by the mandatory `MCP-Protocol-Version` header, which no
form or simple request can set and which forces a preflight.

**Resource exhaustion.** Nothing became unbounded:

- body cap is exact (1 048 576 served / 1 048 577 → 413) and is a single bounded read;
- **slowloris**: header sent, `Content-Length: 500000` declared, one byte dribbled every 12 s —
  Bandit's body read timeout fired at ~15 s (`** (Bandit.HTTPError) Body read timeout`) and the
  socket was closed by t=36 s. The connection cannot be held indefinitely;
- **lying `Content-Length`** (declare 5 000 000, send 100 bytes, stop): no response, connection
  closed on timeout, nothing retained;
- **40 concurrent 1 MiB bodies**: all `200`, total 54 ms. `Server.new/1` is built per request
  from an immutable keyword list and the module holds no ETS, `persistent_term` or process
  state, so there is no shared mutable surface for requests to interfere through;
- **deeply nested JSON**: 100 000-deep array → `400` "Expected a JSON object, got an array";
  50 000-deep nested value inside an object → handled, `200`, no crash;
- **reflection amplification**: a 900 KB `id` comes back in the error response — 900 305 bytes
  out for 900 KB in, ~1:1, and only after `authorize`. Not an amplifier;
- listener survived every crash class; the request after each one succeeded.

**Injection.** No attacker-controlled bytes reach a response *header*. `conn.method` is echoed
into the `405` JSON body but Bandit rejects a malformed request line before the Plug sees it
(`FOO"</script> /mcp HTTP/1.1` → Bandit's own `400`), and `Jason.encode!` escapes the body.
`Origin` is never echoed. Content-Type is unvalidated (`text/plain`,
`application/x-www-form-urlencoded`, absent — all served) but, per above, the mandatory custom
header already forecloses the simple-request CSRF that would exploit it.

---

## Summary

The design decision under review is sound and is implemented as claimed: I attacked the
required-options contract from ten directions and it refused every one, and the protocol-version
header does close the era half of SCR-255. Findings 1 and 2 are not about that decision — they
are about the package applying its own stated rule ("an HTTP caller learns only that the request
failed") to the crash branch while the two branches on either side of it hand out the host's
refusal term and a bare empty 500 respectively. Both are small fixes; both are on paths an
unauthenticated caller reaches.

Finding 10 is the one I would not let ship silently in prose: the README sentence at line 128
is doing more work than the code supports.

VERDICT: changes required
