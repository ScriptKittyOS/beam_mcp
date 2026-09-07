<!--
SPDX-FileCopyrightText: 2026 Sudo Apt Holdings LLC
SPDX-License-Identifier: Apache-2.0
-->

From: beam_mcp · Security lane s1
To: beam_mcp · Coding Agent
Re: slice 002-streamable-http, round 2, HTTP attack surface
Type: Report

**Tree reviewed:** `a5cfb67b8a8854714cde36522292c9fc57e96d6a`
(`git write-tree` in `/home/aylac/Projects/beam_mcp-wt/002-review2`, clean index, also written
to `logs-s1.tree` there). Delta reviewed against `babfc5e40…`. Gate green here too:
`mix test` → **82 tests, 0 failures**; `./tools/gate.sh` → **Gate OK**.

Same method as round 1: real `Bandit` listeners on `127.0.0.1`, raw `:gen_tcp` client, exact
bytes on the wire.

**Both round-1 blockers are fixed and I verified them by re-running the exploits.** Every other
fix you listed I also re-ran; all hold. You asked me to attack `check_headers/2` specifically
and to find a way past it before a consumer does. I did not get past it — but I crashed it,
eight ways, and the two blocking findings below are both round-1 findings that were fixed
*pointwise* and have come back *as a class* inside the new code.

---

## Confirmed fixed (I re-ran each exploit against this tree)

| round 1 | verification on `a5cfb67` |
|---|---|
| **1 — `inspect(reason)` leak** | Same planted payload (`%{expected_bearer: "s3cr3t-token-abc", db: "postgres://user:pw@10.0.0.5/prod"}`) → `403 {"error":{"code":-32600,"message":"Forbidden"},...}`. Grepped the full response: `s3cr3t` **false**, `postgres` **false**. Reason present in the log only. `http.ex:205-212`. |
| **2 — non-map `_meta` bare 500** | `"x"`, `7`, `[1,2]`, `true` → all `400` `-32020` "`_meta` must be a JSON object when present". `http.ex:298-304`. |
| **3 — `throw`/`exit` uncaught** | `raise` / `exit(:SECRET_exit_reason)` / `throw(:SECRET_thrown)` → all three now `500` with `{"error":{"code":-32603,"message":"Internal error"},"id":1,...}`, and `SECRET` absent from every body. `http.ex:376-379`. |
| **4 — first `Origin` only** | `Origin: https://app.example.com` + `Origin: https://evil.com` → **403** (was 200). Reversed → 403. Absent → passes. Case, trailing slash, trailing space, `null` → 403. `http.ex:181-191`. |
| **7 — `authorize` returning `false`** | `403 Forbidden` + `Logger.error`, no `WithClauseError`, no bare 500. `http.ex:214-221`. |
| **10 — README era vs lifecycle** | Read the new text; it now says what the code does. Good. |
| **11 — `init_mode: :runtime`** | Documented at `http.ex:42-46`, and the guarantee stated there ("before any message is handled") is the one that actually holds in both modes. Agreed, no change wanted. |
| **keep-alive on refusal paths** | The one I most wanted to check, since your diagnosis differs from your old changelog. Eight refusal paths, 16 KB bodies, two requests down one socket: `403 origin`, `403 authorize`, `400 bad JSON`, `400 array body`, `400 missing Mcp-Method`, `400 header mismatch`, `404 unknown method` — **second request answered normally in every case**. `413` closes the socket by design (`Connection: close`, `http.ex:411`), second request `{:error, :closed}`, which is correct. |

Also re-verified unchanged from round 1: contract evasion refused on all seven wirings I tried
(`init([])`, partial options, no `tool_catalog`, bare Bandit module, `Plug.Builder` with no
opts, `Plug.Router` `forward` with no `init_opts`); body cap still exact (1 048 576 served /
1 048 577 → 413); 40 concurrent 1 MiB bodies → all answered in 24 ms with no shared state; the
`Allow: POST` header is a nice addition on the 405.

---

## 1. BLOCKING — `check_headers/2` and the refusal path sit outside every rescue, and eight inputs crash them into the bare empty 500 you just eliminated

This is round-1 finding 2. `_meta` was fixed at `http.ex:298-304`; the **class** was not. The
new `check_headers/2` (`http.ex:269-358`) reaches into attacker-shaped JSON, string-interpolates
attacker-supplied values, and JSON-encodes attacker-supplied header bytes — and none of it is
inside the `rescue`/`catch` at `http.ex:372-380`, which wraps only `do_dispatch/3`. The `else`
clause at `http.ex:164-166` matches `{:refused, …}` and nothing else, and `send_json/3`
(`http.ex:403-407`) is called from it, also unprotected.

Eight reproducers, one listener (`authorize: fn _ -> :ok end`, the documented "accept every
caller"), every response `HTTP/1.1 500 Internal Server Error` with an **empty body**:

**(a) `params` is not a map — `get_in/2` at `http.ex:355`**

```
POST /mcp   MCP-Protocol-Version: 2026-07-28   Mcp-Method: tools/call   Mcp-Name: echo
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":"x"}
```
→ `500`, empty body. Log:
```
** (FunctionClauseError) no function clause matching in Access.get/3
```
Same with `"params":[1,2]` (`ArgumentError`, "the Access module supports only keyword lists")
and `"params":7` (`FunctionClauseError`). `check_name_header/3` does exactly what
`body_protocol_version/1` was written to stop doing, three functions further down the same
module.

**(b) a non-string body value interpolated into the mismatch message — `String.Chars`**

`http.ex:347` (`"#{header_name} header '#{value}' does not match body value '#{body_value}'"`)
and `http.ex:316` (same shape for the version).

```
Mcp-Method: x
{"jsonrpc":"2.0","id":1,"method":{"a":1}}
```
→ `500`, empty. `** (Protocol.UndefinedError) protocol String.Chars not implemented for Map`

```
Mcp-Method: ping
{"jsonrpc":"2.0","id":1,"method":"ping","_meta":{"io.modelcontextprotocol/protocolVersion":{"a":1}}}
```
→ `500`, empty. Same exception, from `http.ex:316`. `_meta` being a map is now checked; the
**value at the version key** is not, and it is any JSON value.

```
… "_meta":{"io.modelcontextprotocol/protocolVersion":[{"a":1}]}
```
→ `500`, empty. `** (ArgumentError) cannot convert the given list to a string`

```
Mcp-Method: tools/call   Mcp-Name: echo
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":{"a":1}}}
```
→ `500`, empty. `Protocol.UndefinedError`, from `http.ex:347` via `check_name_header/3`.

**(c) invalid UTF-8 in a validated header — `Jason.EncodeError` inside `send_json/3`**

Two bytes on the wire. Header values are octets; nothing validates them, and both the `-32022`
payload (`"requested" => header`, `http.ex:330`) and the interpolated mismatch string carry them
into `Jason.encode!`.

```
MCP-Protocol-Version: \xFF\xFE
Mcp-Method: ping
{"jsonrpc":"2.0","id":1,"method":"ping"}
```
→ `500`, empty. `** (Jason.EncodeError) invalid byte 0xFF in <<255, 254>>`

```
MCP-Protocol-Version: 2026-07-28
Mcp-Method: \xFF\xFE
```
→ `500`, empty. `Jason.EncodeError`, the whole mismatch sentence in the log.

```
Mcp-Name: \xFF\xFE   (on tools/call)
```
→ **no response at all**; connection closed.

Control: the same request with `MCP-Protocol-Version: 1999-01-01` gives the correct
`400 -32022`. And a body-sourced `id` is safe — `Jason.decode` rejects invalid UTF-8 first
(`{"id":"\ud800"}` → `400 -32700`), so this is specifically the header path.

**What an attacker gains:** the same three things as round 1, now via the code added to close
round 1. (a) The "every refusal is a JSON-RPC error" property is false again, for inputs
cheaper than any test covers — two header bytes, or one JSON scalar in the wrong place.
(b) An unhandled exception escapes the Plug into the host's error handling; a host that wraps
this in `Plug.Debugger` for dev renders stacktrace and source into the response. (c) A free
formatted-stacktrace log-flood primitive at ~60 bytes a request. The `Mcp-Name` case does not
even produce a status line.

**The pointwise fix is not the fix.** Three suggestions, in order of how much I trust them:

1. Wrap the whole of `call/2` — not just `do_dispatch/3` — in the existing `rescue`/`catch`,
   emitting the same detail-free `-32603`. That converts this entire class, including the ones
   I have not thought of, into the answer the module already gives for host crashes.
2. In `check_standard_header/4` and `compare_versions/3`, render non-binary body values with
   `inspect/1`, never interpolation; and reject a `_meta` version value that is not a string the
   way `body_protocol_version/1` already rejects a non-map `_meta`.
3. Reject a header value that is not valid UTF-8 (`String.valid?/1`) as a `400 -32020` before it
   can reach `Jason.encode!`; and reject a non-map `params` on `tools/call` the same way.

## 2. BLOCKING — `Mcp-Method`, `Mcp-Name` and `MCP-Protocol-Version` validate only the *first* header value

`http.ex:335-350` (`[value | _]`) and `http.ex:282` (`List.first/1`).

This is round-1 finding 4, which you fixed for `Origin` in this round with `Enum.all?` — and the
new headers land the same bug in the one place where the spec states the attack as its reason.
Your own comment at `http.ex:260-264` quotes it:

> *This prevents potential security vulnerabilities when different components in the network
> rely on different sources of truth (e.g., a load balancer routing on the header value while
> the MCP server executes based on the body value).*

Two `Mcp-Method` values is precisely "different components relying on different sources of
truth". Measured:

```
POST /mcp
MCP-Protocol-Version: 2026-07-28
Mcp-Method: tools/call
Mcp-Method: ping
Mcp-Name: echo
{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"echo","arguments":{}}}
```
→ `HTTP/1.1 200 OK`, **`tools/call` executed**.

```
Mcp-Name: echo
Mcp-Name: evil
… body params.name = "echo"
```
→ `200 OK`, `echo` executed.

```
MCP-Protocol-Version: 2026-07-28
MCP-Protocol-Version: 1999-01-01
```
→ served (the second is ignored).

**What an attacker gains:** desync with any intermediary that resolves duplicate headers to the
last value, or joins them — which is the documented behaviour of several proxies, and the
attack the MUST exists to prevent. A gateway that authorises or routes on `Mcp-Method: ping`
forwards a request this server executes as `tools/call`. Note that with `Origin` the direction
of the bug was fail-open only in one order; here the *first* value is the one that has to
match the body, and an attacker controls both, so they can always satisfy this server while
presenting whatever they like to the hop in front.

Same one-line shape as the `Origin` fix: require every value to match, and treat more than one
distinct value as a mismatch. `Enum.all?(get_req_header(conn, header_name), &(&1 == body_value))`
with `[]` still "missing", and the same for the version header.

## 3. NON-BLOCKING — the new `404` is too broad: an unknown *tool* is not an unimplemented *method*

`http.ex:393-396` matches `%{"error" => %{"code" => -32_601}}` anywhere in the response. But
`server.ex:224` also returns `-32601` for `"Unknown tool: #{name}"`, which is a *valid,
implemented* method (`tools/call`) with a bad parameter. Measured:

| request | status | body |
|---|---|---|
| `{"method":"frobnicate"}` | `404` | `-32601 Method not found: frobnicate` — correct |
| `tools/call` naming a tool that does not exist | **`404`** | `-32601 Unknown tool: nosuch` |
| `ping` at the modern era | `404` | `-32601 Method not found: ping` — correct |

The spec paragraph you implemented says the `404` exists so the JSON-RPC body *"distinguishes
this case from a `404` returned by a legacy HTTP+SSE server that does not host the modern MCP
endpoint"* — i.e. a client's transport-fallback algorithm reads the status. A typo in a tool
name now tells that client the endpoint may not be there. Match on the *method* being
unimplemented rather than on the code, or have the core distinguish "unknown tool" from
"unknown method" with different codes.

## 4. NOTE — `Mcp-Method` is required on notification POSTs, which the revision explicitly leaves undefined

`check_standard_header/4` is called unconditionally from `check_headers/2` (`http.ex:273`).
Measured: `{"jsonrpc":"2.0","method":"notifications/initialized"}` with the header → `202`;
without it → `400 -32020`. Your own archived spec at
`logs/spec-streamable-http.md:100-104` says *"header requirements for notification POSTs are
not defined by this revision."* Being stricter is defensible and the moduledoc table
(`http.ex:54`) says accurately what it does — but it is a deliberate choice about a case the
spec declines to define, and it will refuse notifications a conformant client is entitled to
send. Worth one sentence saying it is a choice.

## 5. NOTE — the new `:tool_catalog` check is truthiness only

`http.ex:135-138`. `init(tool_catalog: "junk", authorize: …, allowed_origins: …)` returns a
working config; the failure arrives per request as a `500 -32603`. The two checks it sits
between verify shape (`is_function/2`, `is_list` + `Enum.all?`); this one verifies only that the
value is not `nil`/`false`. `Code.ensure_loaded?/1` plus a
`function_exported?(mod, :all, 0)` check would make it the same kind of thing as its neighbours.

---

## Your two open questions — my answer: neither blocks

**Round-1 finding 5 (a body-reading `:authorize`).** Does not block, and I would not restructure
the pipeline for it. The exposure is a host that reads the body inside `authorize` to do
per-tool policy and gets a size-dependent endpoint (works at 93 bytes, no response at 100 KB).
That is a documentation hole, not a defect in these bytes: one sentence on the `:authorize`
option saying it must not read the body, and that per-tool policy belongs in the host's
`dispatch`, closes it completely. I would rather have the sentence than a bigger `call/2`.

**Round-1 finding 6 (no path check).** Does not block. It is host wiring, and a host that wants
one path mounts the Plug behind a router. If you want the moduledoc's first line ("at one
endpoint") to be literally true of the documented usage, the `Bandit.child_spec` example could
show the `Plug.Router` `forward` form instead — cosmetic, and I would not spend the slice on it.

---

## Attacks that failed this round

Everything in round 1's "attacks that failed" list, re-run and still failing, plus:

- **Getting past `check_headers/2`.** No bypass found. `Mcp-Method` must equal the body's
  `method` and `Mcp-Name` must equal `params.name` for `tools/call`, both exact-string, no
  case folding, no normalisation; a missing header is a `400`, not a skip; `check_name_header/3`
  cannot be dodged by changing the method, because the method itself is pinned to the header
  one line earlier. Duplicate values (finding 2) are a desync against *intermediaries*, not a
  way to make this server execute something its own headers did not describe.
- **Era forgery**, again: missing / `1999-01-01` / body-`_meta` disagreeing → `400` `-32020` or
  `-32022`; `do_dispatch/3:386-387` still overwrites `_meta` unconditionally, so no non-modern
  or absent era reaches `handle_message/2`.
- **id-less `tools/call`** → `202`, no dispatch (`server.ex:242` catch-all). Still no path from
  a notification to host code.
- **`tools/call` with no `params`** → `400 -32020` on `Mcp-Name`, before the core.
- **Information disclosure to an unauthenticated caller**: the only things reachable before
  `authorize/1` are the `403 Origin not allowed`, the `405` with `Allow: POST`, and the
  detail-free `403 Forbidden`. Nothing else. The crash class in finding 1 is *behind*
  `authorize`, exactly as in round 1 — which matters only as much as `authorize: fn _ -> :ok end`
  is common, and for a localhost MCP server it is the documented default posture.

---

## Summary

The two round-1 blockers are genuinely closed, the `throw`/`exit` and `Origin` fixes are right,
and the keep-alive diagnosis is correct — I confirmed it across eight refusal paths with bodies
large enough to expose it. The new header validation is good work and I could not get past it.

What I would say to the coding agent, plainly: both blockers this round are the same two
findings from last round, fixed at the site and not at the class. `_meta` no longer crashes;
`params`, the `_meta` version value, `method`, `params.name` and three header values all still
do, and they all crash in the region of `call/2` that has no rescue at all — which is why I
would spend the fix on wrapping `call/2` rather than on five more guards. `Origin` now checks
every value; the three headers added in the same commit check the first.

VERDICT: changes required
