From: beam_mcp · Reviewer lane r2
To: beam_mcp · Coding Agent
Re: slice 002-streamable-http, round 2, resilience and failure behaviour
Type: Report

Tree reviewed: `a5cfb67b8a8854714cde36522292c9fc57e96d6a`
(`cd /home/aylac/Projects/beam_mcp-wt/002-review2 && git write-tree`; also written to
`logs-r2.tree` in that checkout)

## How I measured

Re-run, not read. `lib/` and `test/` copied from the review checkout (`diff -r` → identical for
both) into a throwaway probe tree with a fresh `_build` for `beam_mcp`; a real Bandit 1.12.5
listener on `127.0.0.1:4721`; raw sockets for keep-alive, partial writes and lying
`Content-Length`. Every script edit asserted its match count before writing. Probe-catalog
discipline as before, and the proof re-run against this tree first:

```
PROOF mode reaches dispatch: True     # {"mode":"echoback"} echoed back, 200
```

`mix test` in the probe copy: **82 tests, 0 failures** — matches your claim.

---

# Part 1 — the three round-1 findings

## Finding 1 (stale conn in `else`) — FIXED, and I pushed harder than your check

`http.ex:148-167`. Every step returns `{:ok, conn}` and every refusal carries the conn it was
handed. I ran **19 early-return paths × two body sizes**, two requests on one socket:

```
                            pad=16 KB                pad=200 KB
baseline 200                req1 200  next 200       req1 200  next 200
403 bad Origin              req1 403  next 200       req1 403  next 200
403 authorize deny          req1 403  next 200       req1 403  next 200
405 wrong method            req1 405  next 200       req1 405  next 200
400 missing proto hdr       req1 400  next 200       req1 400  next 200
400 proto mismatch          req1 400  next 200       req1 400  next 200
400 unsupported version     req1 400  next 200       req1 400  next 200
400 missing mcp-method      req1 400  next 200       req1 400  next 200
400 mcp-method mismatch     req1 400  next 200       req1 400  next 200
400 missing mcp-name        req1 400  next 200       req1 400  next 200
400 mcp-name mismatch       req1 400  next 200       req1 400  next 200
400 invalid JSON            req1 400  next 200       req1 400  next 200
400 non-object JSON         req1 400  next 200       req1 400  next 200
400 _meta not a map         req1 400  next 200       req1 400  next 200
404 unknown method          req1 404  next 200       req1 404  next 200
500 rescued raise           req1 500  next 200       req1 500  next 200
500 throw                   req1 500  next 200       req1 500  next 200
500 exit                    req1 500  next 200       req1 500  next 200
202 notification            req1 202  next 200       req1 202  next 200
```

Nothing hangs. The four paths your `keepalive.txt` does not cover — 403 origin, 403 authorize,
405, and the two new header refusals — are clean too. Closed.

## Finding 2 (`throw`/`exit`) — FIXED

`http.ex:376-380`. Measured against a live listener:

```
raise   500  {"error":{"code":-32603,"message":"Internal error"},"id":1,...}
throw   500  {"error":{"code":-32603,"message":"Internal error"},"id":1,...}
exit    500  {"error":{"code":-32603,"message":"Internal error"},"id":1,...}
gexit   500  {"error":{"code":-32603,"message":"Internal error"},"id":1,...}
kill    <no bytes; connection closed>
```

`gexit` is a real `GenServer.call` timeout. All four now carry a body. `kill` still returns
nothing — nothing can answer from a process that no longer exists — so if the CHANGELOG says
"all three", keep it to the three; `Process.exit(self(), :kill)` is outside what `catch` covers.

## Finding 3 (non-map `_meta`) — FIXED

`http.ex:298-304`. `"_meta":"x"` and `"_meta":[1]` → `400`, `-32020`,
`"_meta must be a JSON object when present"`. `"_meta":null` still passes to 200. Closed.

---

# Part 2 — new findings in the round-2 code

## R2-1. HIGH — the crash class this round was convened to close is reintroduced at three new sites in the new header validation

The `Mcp-Method` / `Mcp-Name` validation added this round reaches into attacker-controlled JSON
without checking its shape, in `check_headers/2` at `:162` — which runs in `call/2`, **outside**
`dispatch/3`'s `rescue`/`catch`. Bare empty 500, stacktrace in the log, exactly what finding 3
was about.

```
params is a string        HTTP/1.1 500 Internal Server Error   (no body)
params is an array        HTTP/1.1 500 Internal Server Error   (no body)
params is a number        HTTP/1.1 500 Internal Server Error   (no body)
params.name is a map      HTTP/1.1 500 Internal Server Error   (no body)
method is a map           HTTP/1.1 500 Internal Server Error   (no body)
_meta version is a map    HTTP/1.1 500 Internal Server Error   (no body)
```

Three distinct sites, from the log:

```
** (FunctionClauseError) no function clause matching in Access.get/3
    lib/beam_mcp/transport/http.ex:355: BeamMCP.Transport.HTTP.check_name_header/3
    lib/beam_mcp/transport/http.ex:274: BeamMCP.Transport.HTTP.check_headers/2
    lib/beam_mcp/transport/http.ex:162: BeamMCP.Transport.HTTP.call/2

** (ArgumentError) the Access module supports only keyword lists (with atom keys), got: "name"
    lib/beam_mcp/transport/http.ex:355: BeamMCP.Transport.HTTP.check_name_header/3

** (Protocol.UndefinedError) protocol String.Chars not implemented for Map
    lib/beam_mcp/transport/http.ex:347: BeamMCP.Transport.HTTP.check_standard_header/4
    lib/beam_mcp/transport/http.ex:316: BeamMCP.Transport.HTTP.compare_versions/3
```

- `:355` — `get_in(message, ["params", "name"])`. `params` is any JSON value; a string, array or
  number is not `Access`-able. This is the identical construct to the one you just removed from
  `:212`, moved to a new line.
- `:347` — `"...does not match body value '#{body_value}'"` where `body_value` is
  `message["method"]` or `params["name"]`. A map has no `String.Chars`.
- `:316` — the same interpolation on `_meta`'s protocol version.

The guard at `:298-304` fixed the container. These three fix nothing about the *values*, and the
suite does not reach them: **no test in `http_test.exs` sends a non-map `params`, a non-string
`method`, or a non-string `_meta` version** (`grep -c '"params" => "'` → 0). 82 green tests, three
open crash paths.

**What a host experiences.** `{"params":"x"}` with otherwise valid headers is a stacktrace per
request and a bodyless 500, at will, pre-tool-dispatch. Same as finding 3, one round later.

## R2-2. HIGH — the host's `authorize/1` callback has no crash handling at all

`http.ex:159` calls `authorize/2`, whose `:206` invokes the host's function. It is not inside
`dispatch/3`'s `rescue`/`catch`.

```
x-auth: deny    403  {"error":{"code":-32600,"message":"Forbidden"},...}   (reason logged, not leaked)
x-auth: bogus   403  {"error":{"code":-32600,"message":"Forbidden"},...}   (fail-closed, good)
x-auth: raise   500  (no body)
x-auth: throw   500  (no body)
x-auth: exit    500  (no body)
```

```
** (RuntimeError) authorize exploded AUTHSECRET
    lib/beam_mcp/transport/http.ex:206: BeamMCP.Transport.HTTP.authorize/2
    lib/beam_mcp/transport/http.ex:159: BeamMCP.Transport.HTTP.call/2
```

This is finding 2's shape on the *other* host callback, and the comment at `:362-365` states the
reasoning that applies to it verbatim: "`GenServer.call` timing out EXITS, which is the shape a
host that calls a backend hits first". An `authorize/1` that checks a session store, Redis, or a
database is exactly a host calling a backend — and it runs on the one branch that is by
definition unauthenticated, so this is the callback an attacker can reach without credentials.
The `other ->` clause at `:214-221` shows you already thought about `authorize` returning
something wrong; returning *nothing at all* is the commoner failure.

Leak check passed: `AUTHSECRET` / `SECRETAUTHREASON` appear 4× in the log and 0× in any response
body. The `:201-204` fix holds.

## R2-3. MEDIUM-HIGH — the `authorize/1` contract makes body-based authentication structurally impossible, and it fails as a 15-second timeout

`authorize` at `:159` runs **before** `read_body_bounded` at `:160`, and its contract returns only
`:ok | {:error, term()}` — there is no channel for the host to hand back the conn it read from.
So a host that authenticates the way this kind of endpoint is normally authenticated — an HMAC
over the request body — must call `read_body` itself, and then cannot return the consumed conn.

Measured, with an `authorize` that reads the body and returns `:ok`:

```
pad=100      0.00s  HTTP/1.1 200 OK
pad=16000   15.01s  HTTP/1.1 408 Request Timeout
pad=200000  15.00s  HTTP/1.1 408 Request Timeout
```

and on a keep-alive connection both the 16 KB and 200 KB cases time out on req1 *and* req2. The
server-side log confirms the host's read succeeded (`AUTHORIZE READ 200130 BYTES`); the
transport's own `read_body` then waits 15 s for bytes that are gone.

Small bodies pass because they were already in the adapter buffer — the same size-dependence that
hid finding 1, so this will read as "works" in any test written the way the current ones are.

**What a host experiences.** A correct, conventional signature-verifying `authorize/1` turns
every request over ~16 KB into a 15-second hang and a 408. Nothing in the moduledoc says the
callback must not touch the body. Either say so in the `:authorize` contract at `:33-34`, or let
it return `{:ok, conn}`.

## R2-4. MEDIUM — an unknown *tool* now answers 404, which is what tells a client the endpoint is gone

`http.ex:393-396` maps any `-32601` to 404. That is right for an unimplemented method. It also
catches `Unknown tool:`, which `server.ex:222` emits with the same code:

```
unknown METHOD  404  {"error":{"code":-32601,"message":"Method not found: no/such/method"}}
unknown TOOL    404  {"error":{"code":-32601,"message":"Unknown tool: nosuchtool"}}
```

The comment at `:394-395` gives the reason for the mapping — a client's transport-fallback
algorithm reads the status. By that reasoning, answering 404 to a well-formed `tools/call` for a
tool that happens not to exist tells that algorithm the *endpoint* is absent, and a client can
abandon a working endpoint because it asked for a tool name it got wrong. Discriminate on
something narrower than the code, or have the core distinguish the two.

## R2-5. LOW — a JSON array of small integers is rendered as text in `-32020` messages

Same interpolation sites as R2-1. `"method": [1]` does not crash; it produces

```
mcp-method header 'tools/list' does not match body value '<0x01>'
```

because a list of small integers is a charlist. `[104,105]` would report the body value as `hi`.
Harmless, but the error message asserts something about the request that is not true.

---

# Part 3 — the three items you escalated, with reasoning

## E1 — no `read_timeout` passed to Bandit. **Not blocking.** And I have to correct myself first.

**My round-1 characterisation was wrong.** I wrote that a slow-drip client is "held for as long
as the client keeps trickling under the timeout". It is not. I only watched 10 s. Measured
properly this round, at two drip rates:

```
drip 1.0s/byte:  server answered at 15.0s -> HTTP/1.1 408 Request Timeout
drip 0.2s/byte:  server answered at 15.0s -> HTTP/1.1 408 Request Timeout
```

**15.0 s is a whole-body deadline, not a per-read reset.** A client cannot extend it by dripping
faster. Withdraw the round-1 sentence.

**Which default, and what it is.** Bandit's, not the package's:
`deps/bandit/lib/bandit/http1/socket.ex:251`, `:302`, `:333` — `Keyword.get(opts, :read_timeout,
15_000)`. `http.ex:226` passes only `length:`, so it inherits 15 000 ms. Plug documents the same
default at `plug/lib/plug/conn.ex:1167-1168`. It is overridable per call:
`read_body(conn, length: …, read_timeout: …)`.

**What it costs.** I opened slow connections that declare a body and never finish it:

```
5,000 held    +43 MiB   (8.8 KiB/conn)   legitimate request while held: 200 OK in 0.00s
16,500 held   +243 MiB  (15.1 KiB/conn)  legitimate request while held: 200 OK in 0.00s
28,229 held   +198 MiB  (7.2 KiB/conn)   -- my client ran out of loopback ephemeral ports here
```

I could not find the server's refusal point: at 28,229 the limit I hit was my own client's source
ports, not Bandit's acceptance. Service was not degraded at 16.5k held.

**Why it is acceptable to ship.** The bound exists, it is 15 s, it comes from a dependency default
the package inherits rather than defeats, and the resource a slow client can pin is ~15 KiB of
connection state with no measured effect on other callers. The package is not introducing an
unbounded hold. What it should do is **document the number** — because a host that wants a
different one needs to know the knob is `read_body`'s `:read_timeout`, that the package currently
does not pass it, and that 15 s is what it gets by default. That is a doc change. If you would
rather make it explicit in code, passing `read_timeout: 15_000` at `:226` changes no behaviour and
makes the inherited value visible; I would not block on either.

## E2 — no aggregate body bound. **This one should not ship silently.** Blocking as documentation.

**N concurrent requests, each a body of exactly 1,048,574 bytes (the cap), each held in dispatch
so its body stays resident. RSS of the BEAM, sampled while in flight:**

```
N        delta RSS     per request     all succeeded
1        +2.0 MiB      2048 KiB        1/1
10       +19.9 MiB     2037 KiB        10/10
50       +87.9 MiB     1801 KiB        50/50
100      +104.3 MiB    1068 KiB        100/100
250      +275.3 MiB    1128 KiB        250/250
500      +442.3 MiB     906 KiB        500/500
1000     +972.5 MiB     996 KiB        1000/1000
2000     +1.92 GiB      983 KiB        2000/2000
4000     +4.31 GiB     1102 KiB        4000/4000
8000     +8.16 GiB     1044 KiB        8000/8000
```

Linear at ~1.05 MiB of RSS per in-flight at-cap request, **no plateau, nothing refused**. 8,000
concurrent well-formed requests cost 8.16 GiB and all 8,000 got 200 OK.

**Where it stops being fine is a function of the connection ceiling, and I had that wrong in round
1 too.** I said "~16k". From source: `deps/thousand_island/lib/thousand_island.ex:130-137` —
`num_connections` is **per acceptor**, and "the maximum number of concurrent connections for the
server is `num_acceptors * num_connections`". Defaults are `num_connections: 16_384`
(`server_config.ex:36`) and `num_acceptors: 100` — verified live on this tree, the acceptor pool
has exactly 100 children. **The default ceiling is 100 × 16,384 = 1,638,400 concurrent
connections**, which at the measured 1.05 MiB each is ~1.7 TiB of at-cap bodies. There is no
aggregate bound from the package, and none in practice from Bandit's defaults either.

**Why I would not have the package add a limiter.** A library that silently caps a host's
concurrency is worse than one that does not: the host owns its capacity planning, and a cap the
package picks is a number it cannot keep, in exactly the sense the moduledoc already argues for
`authorize` and `allowed_origins`. So the code is right and the documentation is not.

**What `README.md` must say for a host to get this right** — it currently says only "Request
bodies are capped at 1 MiB", which reads as a resource bound and is not one:

1. The cap is **per request**, and memory is **~1 MiB per request in flight**, measured — so the
   memory ceiling is that times the concurrency the host permits.
2. The concurrency the host permits defaults to `num_acceptors × num_connections` =
   **1,638,400**, and setting it is the host's job (`Bandit.child_spec(thousand_island_options:
   [num_connections: …])`).
3. `@max_body_bytes` is a **floor on what is read**, not a ceiling: measured read-before-refusal
   was up to **1,769,325 bytes** for a declared 32 MiB body — Plug's `:length` is a threshold, and
   Bandit reads in chunks past it.

That is the answer the owner needs to be able to give deliberately: *the package bounds one
request; nothing bounds the sum; here is the host setting that does.*

## E3 — non-encodable dispatch payloads become 500. **Not blocking.**

Re-measured on this tree:

```
{:ok, {:a, :b}}            500  {"error":{"code":-32603,"message":"Internal error"},"id":1,...}
{:ok, %{"pid" => self()}}  500  {"error":{"code":-32603,"message":"Internal error"},"id":1,...}
```

Keep-alive survives both (verified in the Part 1 matrix). No detail leaks. `Jason.EncodeError`
reaches the log with the offending value.

**Why it is acceptable to ship.** It is a host bug — returning a term that is not JSON from a
callback whose contract is a JSON-RPC result — and every property that matters holds: it is
caught, the answer is well-formed JSON-RPC, the connection is not poisoned, the caller learns
nothing about the host, and the host learns everything from the log. Nothing about it is a
resilience defect.

What is imperfect is the *label*. The host is told "Internal error" where "your tool returned a
term I cannot encode" would save it a debugging session, and the client is told the server failed
where `"isError": true` would be truer to what happened. That is diagnosability, and it is also
genuinely arguable the other way: `tool_failure/1` is for a tool *reporting* failure, and a
payload the transport cannot serialise is a contract violation rather than a tool outcome, so 500
is defensible. I would file it, fix it when convenient, and note that the fix belongs at
`server.ex:264` (`tool_success/1`) rather than in the transport — the transport cannot tell an
unencodable payload from any other raise once it is in the rescue.

---

# Part 4 — re-run and unchanged

Recorded so it is not re-run again. All against this tree.

- **Malformed input answers rather than crashing**, except R2-1: empty body, whitespace, invalid
  JSON, bare `null`/number/string, `[]`, lone surrogate, raw invalid UTF-8, `NUL` in a string,
  duplicate keys, `id` as an object, no `method` key — all a JSON-RPC answer.
- **Depth and size**: 260,000-deep nested arrays, 100,000-deep nested objects, a 1 MB single
  string, 50,000 duplicate keys — all 200 OK in ≤ 0.03 s.
- **Cap boundary**: 1 MiB − 1024 → 200; exactly 1 MiB → 200; 1 MiB + 1 → 413; 4 MiB → 413;
  32 MiB → 413. Chunked encoding capped identically.
- **Lying `Content-Length`**: over-declared → 408 at 15.00 s (see E1); under-declared → 400 parse
  error.
- **Concurrency**: 100 / 500 / 1000 concurrent `tools/call` with distinct ids and distinct echoed
  arguments — 0 crossed, 0 mismatched, 1000 in 0.17 s.
- **Supervision**: killed the Bandit supervisor, `ThousandIsland.Listener`,
  `acceptor_pool_supervisor` and `shutdown_listener` in turn under a host `one_for_one`; every one
  restarted and the next request was 200 OK. A raising handler leaves the tree untouched.
- **Methods**: all eight non-POST verbs → 405, now with `allow: POST`. Good addition.
- **Content-Type is still not validated** (`text/plain`, form-encoded, absent all reach dispatch)
  and **the path is not checked** (`/`, `/admin`, `/../../etc/passwd` all 200). Both are r1's lane
  — Plug hosts route, and the moduledoc's "at one endpoint" is about the protocol not the router.
  Noting, not filing.

---

## What blocks

R2-1 and R2-2 are the same defect class this round was convened to close, at four new lines, and
none of the four is reachable by the suite. R2-3 breaks a conventional host implementation into a
15-second hang. E2 needs three sentences in `README.md` so the owner is stating the position
rather than discovering it.

R2-4 I would want fixed but would not hold the release for. R2-5, E1 and E3 are file-and-move-on.

VERDICT: changes required
