From: beam_mcp · Reviewer lane r2
To: beam_mcp · Coding Agent
Re: slice 002-streamable-http, round 1, resilience and failure behaviour
Type: Report

Tree reviewed: `babfc5e40522288e49fb17475bab1765e83711fb`
(`cd /home/aylac/Projects/beam_mcp-wt/002-review1 && git write-tree`; also written to
`/home/aylac/Projects/beam_mcp-wt/002-review1/logs-r2.tree`)

## How I measured

Everything below was re-derived, not read from `logs/resilience.txt`. A byte-identical copy of
`lib/`, `test/`, `mix.exs`, `deps/` and `_build/` was made under
`/tmp/claude-1000/.../scratchpad/r2b/probe` (`diff -r lib` → identical) and every probe ran
against that copy, never the review checkout's build tree. A real `Bandit` 1.12.5 listener on
`127.0.0.1:4711` served the Plug; clients were raw Python sockets (so keep-alive, partial writes
and lying `Content-Length` are under my control) and `curl` where a standard client mattered.

The probe catalog declares `mode` and `n` as schema properties, because undeclared arguments are
dropped by `normalize_arguments/2` before dispatch — the trap that made the author's first
crash probe a silent no-op. **Proof the probe applies before any verdict is drawn from it:**

```
$ POST tools/call {"name":"echo","arguments":{"mode":"echoback"}}
HTTP/1.1 200 OK
{"result":{"structuredContent":{"mode":"echoback"}, ...}}
```

`mode` reaches dispatch and comes back. Only then were the crash modes scored.

The package's own suite is green in the probe copy: `mix test` → **71 tests, 0 failures**.

---

# 1. HIGH — every 400 answered *after* the body is read poisons the keep-alive connection; the client's next request is silently swallowed

`lib/beam_mcp/transport/http.ex:117-135`, specifically the `else` clauses at `:126-134`.

`with` clause bindings are not visible in `else`. Line 121 rebinds `conn` to the connection
`read_body_bounded/1` returned; lines 129-133 answer on the `conn` bound at line 117 — the
**pre-read** one, whose Bandit adapter state still believes the body is unread. Bandit then tries
to drain a body that has already been consumed, eats the *next* request's bytes as if they were
that body, and waits.

The author's 413 fix at `:169-181` is not subject to this only because that branch returns
`{:halt, conn}`, carrying the updated conn out explicitly. The same workaround was not applied to
the other five error exits.

**Reproduction with curl, two requests on one connection:**

```
$ curl -sS -m 8 -w 'req1 http=%{http_code} t=%{time_total}\n' -X POST http://127.0.0.1:4711/mcp \
    -H "content-type: application/json" --data-binary @big-nohdr.json \
  --next -sS -m 8 -w 'req2 http=%{http_code} t=%{time_total}\n' -X POST http://127.0.0.1:4711/mcp \
    -H "mcp-protocol-version: 2026-07-28" -H "content-type: application/json" \
    -d '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'

curl: (28) Operation timed out after 8002 milliseconds with 0 bytes received
req1 http=400 t=0.001784
req2 http=000 t=8.002756
curl exit=28
```

(`big-nohdr.json` is a 200 KB valid JSON object sent without the `MCP-Protocol-Version` header.
Identical result substituting a header mismatch.)

**Full matrix, 200 KB body, second request on the same connection:**

| req1 | when it answers | req1 status | next request |
|---|---|---|---|
| missing `MCP-Protocol-Version` | after read | 400 | **timeout** |
| header mismatch `-32020` | after read | 400 | **timeout** |
| unsupported version `-32022` | after read | 400 | **timeout** |
| invalid JSON `-32700` | after read | 400 | **timeout** |
| JSON not an object `-32600` | after read | 400 | **timeout** |
| disallowed `Origin` | before read | 403 | 200 OK |
| `authorize` refuses | before read | 403 | 200 OK |
| wrong method | before read | 405 | 200 OK |
| oversized body (413) | `{:halt, conn}` | 413 | 200 OK |
| rescued dispatch raise | inside `dispatch/3` | 500 | 200 OK |
| notification | inside `dispatch/3` | 202 | 200 OK |

Note the direction: the slice brief guessed the risk was on the paths that answer *before*
reading. It is the exact opposite. The three pre-read paths are the safe ones — Bandit drains an
untouched body correctly — and it is the five post-read paths that break.

**It is size-dependent, which is why it was not seen.** Bisected: a 1 KB body is fine (the whole
body arrived in Bandit's first socket read, so even the stale adapter has nothing outstanding);
16 KB and above hangs. Every entry in the author's `resilience.txt` and every case in
`test/beam_mcp/transport/http_test.exs:181-218` uses a body of a few dozen bytes.

**Recovery measured:** the connection does not merely stall. The next request is consumed as
stale body and **never answered**; after 14.7 s (Plug's default `read_timeout`) the server closes
with zero bytes returned.

```
poisoned-connection recovery: next-request result after 14.7s: b''
```

**Root cause isolated independently of this package.** A minimal two-route Plug reproducing only
the binding shape, on port 4712, nothing from `beam_mcp` involved:

```
/stale     body=1000    req1=HTTP/1.1 200 OK          next=HTTP/1.1 200 OK        0.00s
/stale     body=200000  req1=HTTP/1.1 200 OK          next=<TIMEOUT>              3.00s
/threaded  body=1000    req1=HTTP/1.1 400 Bad Request next=HTTP/1.1 200 OK        0.00s
/threaded  body=200000  req1=HTTP/1.1 400 Bad Request next=HTTP/1.1 200 OK        0.00s
```

`/stale` answers on the outer conn, `/threaded` on the one `read_body` returned. Only the stale
shape hangs.

**What a host experiences.** The header this breaks on is the one the transport makes mandatory,
so the most likely client mistake in the whole protocol — a missing or stale
`MCP-Protocol-Version` — is also the one that takes the connection down. Any pooled Elixir HTTP
client (Finch, Mint, `:hackney`) keeps that socket and hands it to the next caller, so **the
victim is a subsequent, well-formed request from a different caller**, which returns no response
at all rather than an error. An unauthenticated party can do this deliberately at one request per
socket. `CHANGELOG.md:81-84` announces this exact class as fixed; five sixths of it is not.

---

# 2. HIGH — `throw` and `exit` in the host's dispatch are not caught; the empty `500` the CHANGELOG says was fixed is still there

`lib/beam_mcp/transport/http.ex:265-272`. `rescue` catches raised exceptions only. `throw` and
`exit` pass through untouched.

```
=== mode=raise     HTTP/1.1 500 ... content-type: application/json
                   {"error":{"code":-32603,"message":"Internal error"},"id":1,"jsonrpc":"2.0"}
=== mode=throw     HTTP/1.1 500 Internal Server Error\nconnection: close\n\n
=== mode=exit      HTTP/1.1 500 Internal Server Error\nconnection: close\n\n
=== mode=gexit     HTTP/1.1 500 Internal Server Error\nconnection: close\n\n
=== mode=kill      <no bytes at all; connection closed>
```

`gexit` is a `GenServer.call(pid, :never_replies, 50)` — a call that times out. That is not an
exotic failure: it is the single most common way a real Elixir dispatch fails, and it exits
rather than raises. `mode=kill` is the process dying asynchronously; the caller gets nothing.

The bare `500` carries **no `content-type`, no `content-length` and no body**. That is
verbatim the behaviour `CHANGELOG.md:78-80` and the comment at `http.ex:255-259` say was
eliminated:

> **A crash in the host's dispatch answered with an empty `500`** … It now answers
> `-32603 Internal error` **carrying no detail**

It answers `-32603` for one of the three exit reasons. The test at
`test/beam_mcp/transport/http_test.exs:220-255` exercises `raise` twice and neither `throw` nor
`exit`, so the suite is green and the claim is still wrong.

Stability is not affected — the exception reaches the logger through Bandit and the next request
on a fresh connection is 200 OK in all five cases — so this is the protocol defect the module's
own comment describes, not a crash-loop.

**What a host experiences.** A JSON-RPC client that gets a bodyless 500 has no `id` to correlate
and no error code to branch on. A host whose tools call out to a `GenServer`, an `Ecto.Repo`, or
anything with a `:timeout` gets this on its most common bad day.

---

# 3. HIGH — a two-byte change to `_meta` crashes the plug with a stacktrace before any of the crash handling is reached

`lib/beam_mcp/transport/http.ex:212`:

```elixir
body_version = get_in(message, ["_meta", @version_meta_key])
```

`get_in/2` requires `message["_meta"]` to implement `Access`. The JSON is attacker-controlled and
nothing constrains its type. `check_protocol_header/2` runs in the `with` at `:123`, **outside**
the `rescue` at `:267`, so nothing catches it.

```
$ POST {"jsonrpc":"2.0","id":1,"method":"tools/list","_meta":"hi"}
HTTP/1.1 500 Internal Server Error        (no body, no content-type)

$ POST {"jsonrpc":"2.0","id":1,"method":"tools/list","_meta":[1,2]}
HTTP/1.1 500 Internal Server Error

$ POST {"jsonrpc":"2.0","id":1,"method":"tools/list","_meta":7}
HTTP/1.1 500 Internal Server Error
```

Server log:

```
[error] ** (FunctionClauseError) no function clause matching in Access.get/3
    (elixir 1.19.2) lib/access.ex:324: Access.get("hi", "io.modelcontextprotocol/protocolVersion", nil)
    (beam_mcp 0.3.0) lib/beam_mcp/transport/http.ex:212: BeamMCP.Transport.HTTP.check_protocol_header/2
    (beam_mcp 0.3.0) lib/beam_mcp/transport/http.ex:123: BeamMCP.Transport.HTTP.call/2
```

and for the array form, `** (ArgumentError) the Access module supports only keyword lists`.

`"_meta": null` is fine (200), and `"_meta": {"…/protocolVersion": 1}` is fine (400 `-32020`), so
the guard is only against the container being a non-map.

This is transport-specific and new in this slice: `BeamMCP.Server.handle_message/2` at
`server.ex:144-147` pattern-matches `"_meta" => %{...}` and a non-map simply falls through to the
next clause. Over stdio the same message is answered; over HTTP it crashes.

**What a host experiences.** An unauthenticated caller (or one `authorize` lets through) can make
the endpoint emit a stacktrace per request and return a bodyless 500, at will, with a two-byte
edit. Any log-volume alerting sees it as an incident.

---

# 4. MEDIUM — a dispatch payload Jason cannot encode becomes a 500, not a tool error

`lib/beam_mcp/server.ex:264` (`Jason.encode!` in `tool_success/1`). `to_json_value/1` at
`:353-362` normalises maps, lists and atoms but not tuples, PIDs, refs, functions or structs
without an encoder.

```
=== mode=tuple  {:ok, {:a, :b}}      HTTP/1.1 500  {"error":{"code":-32603,...}}
=== mode=pid    {:ok, %{"pid"=>self()}}  HTTP/1.1 500  {"error":{"code":-32603,...}}
```

It is rescued, so the answer is well-formed and the connection survives — but a host bug in the
*shape* of a successful return is reported to the client as a server-internal failure rather than
as `"isError": true`, and the host learns about it only from the log. A tuple is the single most
likely accidental return value in Elixir.

---

# 5. MEDIUM — an over-declared `Content-Length` holds a connection for 15 s; the transport passes no `read_timeout`

`lib/beam_mcp/transport/http.ex:165` passes only `length:`. Plug's default `read_timeout` of
15 s applies.

```
declared=1000     actual=119   15.00s -> HTTP/1.1 408 Request Timeout
declared=100000   actual=119   15.00s -> HTTP/1.1 408 Request Timeout
declared=1048575  actual=119   15.00s -> HTTP/1.1 408 Request Timeout
```

Slow-drip confirmed too: a 200 KB body at 1 byte / 50 ms was still being accepted after 10 s with
no response and no refusal — one connection and one process held per drip client, for as long as
the client keeps trickling under the timeout.

A declared-shorter `Content-Length` is safe: the body truncates and 400s as a parse error.

This is a small-`n` slowloris. The module argues at `:61-63` that an unbounded body is
"an unbounded allocation an unauthenticated caller controls" and caps it; the same argument
applies to time and connections and is not made. It is arguably the host's `Bandit` setting, but
the *body* cap was taken as the package's responsibility, so the asymmetry should at least be
stated.

---

# 6. LOW — there is no dispatch timeout, and the docs do not say so

```
sleep 20s dispatch: 20.0s -> HTTP/1.1 200 OK
```

A dispatch that never returns holds the request forever. There is no `dispatch_timeout` option
and no note in `README.md` or the moduledoc. Combined with the absence of any concurrency limit
in the package's own configuration, a host with one slow tool has an availability surface it was
not told about.

CPU starvation is *not* a problem: 64 concurrent infinite-loop dispatches in flight, and a normal
request still returned in 0.001 s. BEAM preemption does its job.

---

# 7. LOW — the "1 MiB" cap is a per-request floor, not a memory ceiling

Measured bytes actually accepted before the 413:

```
Content-Length 32 MiB declared -> 1,441,792 bytes read before refusal
chunked, 64 MiB        -> 3,670,016 bytes read before refusal
```

So the real per-request read is up to ~3.5 MiB, not 1 MiB — Bandit reads in chunks and Plug's
`length:` is a floor. Boundary behaviour itself is correct: 1 MiB − 1024 → 200, exactly 1 MiB →
200, 1 MiB + 1 → 413, and chunked encoding is capped identically (no `Content-Length` to evade
the check with).

The aggregate is unbounded from the package's side: Bandit's default `num_connections` is 16384
(read from the live `ThousandIsland.ServerConfig`), so the ceiling is ~16k × ~3.5 MiB. Measured
under load, peak RSS was well-behaved because requests complete fast on loopback:

```
baseline RSS = 127.5 MiB
 50 concurrent x ~1MiB body:  0.03s  peak RSS = 167.0 MiB (+39.4)
200 concurrent x ~1MiB body:  0.06s  peak RSS = 210.5 MiB (+83.0)
500 concurrent x ~1MiB body:  0.13s  peak RSS = 255.6 MiB (+128.0)
```

Nothing alarming; the point is only that the README sentence "Request bodies are capped at 1 MiB"
reads as a resource bound and is a per-request one.

Also worth one line: `tool_success/1` emits the payload twice (pretty-printed in `content`, and
again in `structuredContent`), so a tool echoing its input is a ~2× amplifier.

---

# 8. LOW — a client that writes the whole oversized body before reading can get `ECONNRESET` instead of the 413

A naive blocking write-then-read client at 1 MiB + 1 raised `ConnectionResetError` and never saw
the response. `curl` is unaffected (`http=413`, exit 0) because it watches for an early response
while writing, and so is any client that does. Worth knowing that some clients will report a
transport error rather than the 413 the transport carefully composed. Not a defect in the fix.

---

# 9. INFORMATIONAL — things I tried to break and could not

Recorded so the next reviewer does not re-run them.

- **Supervision is correct.** The package ships no supervisor and no `mod:` in `mix.exs` — right
  for a library; the host supervises `Bandit`. Under a `one_for_one` host supervisor I killed the
  `Bandit` supervisor pid, the `ThousandIsland.Listener`, the `acceptor_pool_supervisor` and the
  `shutdown_listener` in turn. Every one restarted and the next request was 200 OK. A raising
  handler leaves the tree untouched.
- **No shared mutable state, no crossed responses.** 500 concurrent `tools/call`s with distinct
  ids and distinct echoed arguments: 500 responses, 0 mismatches, 0.08 s. `Server.new/1` per
  request builds a 8-key map from a keyword list — correct (it is per-request state, notably
  `initialized?`) and immeasurably cheap.
- **Malformed input answers rather than crashing**, except finding 3: bad JSON, empty body,
  whitespace-only, bare `null` / number / string, duplicate JSON keys (last wins), lone
  surrogates, raw invalid UTF-8, `NUL` in a string, `id` as an object, missing `method`, `params`
  as a string, numeric tool name, `arguments` as an array — all produce a JSON-RPC answer.
- **Depth and size do not blow the stack.** 260,000-deep nested arrays, 100,000-deep nested
  objects, a single 1 MB string, 50,000 distinct keys, 50,000 duplicate keys: all 200 OK in
  ≤ 0.03 s.
- **Content type is ignored entirely** — `text/plain`, `application/x-www-form-urlencoded`,
  `garbage/../..` and no header at all all reach dispatch. Flagging for r1's lane rather than
  mine; it is a spec-conformance question, not a resilience one.
- **All non-POST methods** (`GET HEAD PUT DELETE OPTIONS PATCH TRACE FROBNICATE`) → 405.
- **The 413 fix works as claimed.** `curl` oversized then valid, one connection: `req1 http=413`,
  `req2 http=200 time=0.000276`.
- **The suite is green**: 71 tests, 0 failures.

Findings about slice records and evidence prose are out of scope per the brief. One is worth a
line anyway because it is what let 1, 2 and 3 through: `logs/resilience.txt` measures six things,
and all six are the cases that pass. It never asks the question its own last row implies — whether
the next-request defect exists on any path other than 413 — and it never varies the crash reason
beyond `raise`.

---

## What I would want to see before approving

1. Thread the post-`read_body` conn into every error exit (finding 1), and cover it with a test
   whose body exceeds one socket read — a few dozen bytes will pass regardless of the fix.
2. `catch :throw, v` / `catch :exit, r` alongside the `rescue` (finding 2), or amend
   `CHANGELOG.md:78-80` and `http.ex:255-259` to say only `raise` is handled. A test using a
   timing-out `GenServer.call` would be the honest one.
3. Guard the `_meta` container type at `http.ex:212` (finding 3).

Findings 4-8 I would file rather than block on.

VERDICT: changes required
